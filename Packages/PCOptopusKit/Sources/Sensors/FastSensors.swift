import Foundation
import Model
#if canImport(IOKit.ps)
import IOKit.ps
#endif

public struct FastSensorSnapshot: Sendable {
    public var cpuUsedFraction: Double
    public var performanceCores: Int
    public var efficiencyCores: Int
    public var memoryPressure: MemoryPressureValue
    public var compressorBytes: UInt64
    public var swapBytes: UInt64
    public var physicalBytes: UInt64
    public var powerSource: PowerSourceValue
    public var lowPowerMode: Bool
    public var thermalState: ThermalStateValue
    public var preventSleepAssertion: Bool
    public var assertionProcessName: String?
    public var assertionHeldMinutes: Double
    public var clamshell: Bool
    public var ac: PmsetSettings
    public var battery: PmsetSettings

    public init(
        cpuUsedFraction: Double = 0,
        performanceCores: Int = 0,
        efficiencyCores: Int = 0,
        memoryPressure: MemoryPressureValue = .unknown,
        compressorBytes: UInt64 = 0,
        swapBytes: UInt64 = 0,
        physicalBytes: UInt64 = 0,
        powerSource: PowerSourceValue = .unknown,
        lowPowerMode: Bool = false,
        thermalState: ThermalStateValue = .nominal,
        preventSleepAssertion: Bool = false,
        assertionProcessName: String? = nil,
        assertionHeldMinutes: Double = 0,
        clamshell: Bool = false,
        ac: PmsetSettings = PmsetSettings(),
        battery: PmsetSettings = PmsetSettings()
    ) {
        self.cpuUsedFraction = cpuUsedFraction
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.memoryPressure = memoryPressure
        self.compressorBytes = compressorBytes
        self.swapBytes = swapBytes
        self.physicalBytes = physicalBytes
        self.powerSource = powerSource
        self.lowPowerMode = lowPowerMode
        self.thermalState = thermalState
        self.preventSleepAssertion = preventSleepAssertion
        self.assertionProcessName = assertionProcessName
        self.assertionHeldMinutes = assertionHeldMinutes
        self.clamshell = clamshell
        self.ac = ac
        self.battery = battery
    }
}

public struct FastSensors: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = ShellProcessRunner()) {
        self.runner = runner
    }

    public func read(includePmset: Bool = true, includeAssertions: Bool = true) -> FastSensorSnapshot {
        var snap = FastSensorSnapshot()
        snap.physicalBytes = ProcessInfo.processInfo.physicalMemory
        snap.performanceCores = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
        snap.efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        if snap.performanceCores + snap.efficiencyCores == 0 {
            snap.performanceCores = ProcessInfo.processInfo.activeProcessorCount
        }
        snap.cpuUsedFraction = readCPUFraction()
        snap.thermalState = mapThermal(ProcessInfo.processInfo.thermalState)
        snap.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        snap.powerSource = readPowerSource()
        // Skip memory_pressure/vm_stat on the fast tick — those are for the 30s medium pass.
        if includePmset || includeAssertions {
            let mem = readMemoryStats()
            snap.memoryPressure = mem.pressure
            snap.compressorBytes = mem.compressor
            snap.swapBytes = mem.swap
        }
        if includePmset {
            if let custom = try? runner.run("/usr/bin/pmset", arguments: ["-g", "custom"]) {
                let parsed = PmsetParser.parseCustom(custom)
                snap.ac = parsed.ac
                snap.battery = parsed.battery
            }
        }
        if includeAssertions {
            if let text = try? runner.run("/usr/bin/pmset", arguments: ["-g", "assertions"]) {
                let parsed = AssertionParser.parse(text)
                snap.preventSleepAssertion = parsed.preventSleep
                snap.assertionProcessName = parsed.processName
                snap.assertionHeldMinutes = parsed.heldMinutes
            }
        }
        snap.clamshell = readClamshell()
        return snap
    }

    public func sampleBundle(from snap: FastSensorSnapshot, timestamp: Date = Date()) -> SampleBundle {
        var compute = Sample(domain: .compute, timestamp: timestamp)
        compute.set(.cpuUsedFraction, snap.cpuUsedFraction)
        compute.set(.cpuPerformanceCores, snap.performanceCores)
        compute.set(.cpuEfficiencyCores, snap.efficiencyCores)

        var memory = Sample(domain: .memory, timestamp: timestamp)
        memory.set(.memoryPressure, snap.memoryPressure.rawValue)
        memory.set(.memoryCompressorBytes, Double(snap.compressorBytes))
        memory.set(.memorySwapBytes, Double(snap.swapBytes))
        memory.set(.memoryPhysicalBytes, Double(snap.physicalBytes))

        var energy = Sample(domain: .energy, timestamp: timestamp)
        energy.set(.energyPowerSource, snap.powerSource.rawValue)
        energy.set(.energyLowPowerMode, snap.lowPowerMode)
        energy.set(.energyThermalState, snap.thermalState.rawValue)
        if let v = snap.ac.sleep { energy.set(.energyACSleepMinutes, v) }
        if let v = snap.ac.displaysleep { energy.set(.energyACDisplaySleepMinutes, v) }
        if let v = snap.ac.disksleep { energy.set(.energyACDiskSleepMinutes, v) }
        if let v = snap.ac.powernap { energy.set(.energyACPowerNap, v) }
        if let v = snap.ac.womp { energy.set(.energyACWomp, v) }
        if let v = snap.battery.sleep { energy.set(.energyBatterySleepMinutes, v) }
        if let v = snap.battery.displaysleep { energy.set(.energyBatteryDisplaySleepMinutes, v) }
        energy.set(.energyAssertionsPreventSleep, snap.preventSleepAssertion)
        if let name = snap.assertionProcessName {
            energy.set(.energyAssertionProcess, name)
        }
        energy.set(.energyAssertionMinutes, snap.assertionHeldMinutes)
        energy.set(.energyClamshell, snap.clamshell)

        return SampleBundle(timestamp: timestamp, samples: [compute, memory, energy])
    }

    private func mapThermal(_ state: ProcessInfo.ThermalState) -> ThermalStateValue {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private func readPowerSource() -> PowerSourceValue {
        #if canImport(IOKit.ps)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(info, first)?.takeUnretainedValue() as? [String: Any],
              let state = desc[kIOPSPowerSourceStateKey] as? String else {
            return .unknown
        }
        if state == kIOPSACPowerValue { return .ac }
        if state == kIOPSBatteryPowerValue { return .battery }
        return .unknown
        #else
        return .unknown
        #endif
    }

    private func readCPUFraction() -> Double {
        // Lightweight host_statistics path; falls back to 0 on failure.
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(load.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        // Absolute tick ratio is a coarse idle indicator for the menu bar.
        return min(1, max(0, (user + system + nice) / total))
    }

    private func readMemoryStats() -> (pressure: MemoryPressureValue, compressor: UInt64, swap: UInt64) {
        var pressure: MemoryPressureValue = .normal
        // Only use -Q (quick). Full `memory_pressure` can block for a long time.
        if let text = try? runner.run("/usr/bin/memory_pressure", arguments: ["-Q"]) {
            let lower = text.lowercased()
            if lower.contains("critical") {
                pressure = .critical
            } else if lower.contains("warn") {
                pressure = .warning
            }
        }

        var compressor: UInt64 = 0
        var swap: UInt64 = 0
        if let vm = try? runner.run("/usr/bin/vm_stat", arguments: []) {
            let pageSize = UInt64(vm_page_size())
            for line in vm.components(separatedBy: .newlines) {
                if line.contains("Pages occupied by compressor") {
                    compressor = parseVmCount(line) * pageSize
                }
                if line.contains("Swapins") || line.hasPrefix("Swapins:") {
                    // swap bytes approximated later from sysctl if available
                }
            }
        }
        if let swapused = sysctlUInt64("vm.swapusage") {
            _ = swapused
        }
        // Read swap via sysctl string
        var size: size_t = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: Int(size))
            sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)
            let text = String(cString: buffer)
            // xfer/used patterns vary; parse "used = NNN.NNM"
            if let range = text.range(of: #"used =\s*([0-9.]+)([MG])"#, options: .regularExpression) {
                let token = String(text[range])
                let parts = token.replacingOccurrences(of: "used =", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if parts.hasSuffix("M"), let mb = Double(parts.dropLast()) {
                    swap = UInt64(mb * 1024 * 1024)
                } else if parts.hasSuffix("G"), let gb = Double(parts.dropLast()) {
                    swap = UInt64(gb * 1024 * 1024 * 1024)
                }
            }
        }
        return (pressure, compressor, swap)
    }

    private func parseVmCount(_ line: String) -> UInt64 {
        let digits = line.split(separator: ":").last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "") ?? "0"
        return UInt64(digits) ?? 0
    }

    private func vm_page_size() -> Int {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        return Int(pageSize == 0 ? 16384 : pageSize)
    }

    private func readClamshell() -> Bool {
        // ioreg AppleClamshellState — true when lid closed.
        guard let text = try? runner.run("/usr/sbin/ioreg", arguments: ["-r", "-k", "AppleClamshellState", "-d", "1"]) else {
            return false
        }
        return text.contains("\"AppleClamshellState\" = Yes")
    }
}

public enum AssertionParser {
    public struct Result: Sendable {
        public var preventSleep: Bool
        public var processName: String?
        public var heldMinutes: Double
    }

    public static func parse(_ text: String) -> Result {
        if text.contains("No assertions.") {
            return Result(preventSleep: false, processName: nil, heldMinutes: 0)
        }
        var prevent = false
        var name: String?
        for line in text.components(separatedBy: .newlines) {
            if line.contains("PreventUserIdleSystemSleep") {
                prevent = true
            }
            if line.contains("Named:") || line.contains("pid ") {
                // Extract process-like token
                if let range = line.range(of: #"\"([^\"]+)\""#, options: .regularExpression) {
                    name = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        return Result(preventSleep: prevent, processName: name, heldMinutes: prevent ? 1 : 0)
    }
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let result = sysctlbyname(name, &value, &size, nil, 0)
    guard result == 0 else { return nil }
    return Int(value)
}

func sysctlUInt64(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    let result = sysctlbyname(name, &value, &size, nil, 0)
    guard result == 0 else { return nil }
    return value
}
