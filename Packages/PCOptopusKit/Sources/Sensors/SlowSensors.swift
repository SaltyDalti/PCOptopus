import Foundation
import Model

public struct LargeFolderEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var bytes: UInt64

    public init(path: String, bytes: UInt64) {
        self.path = path
        self.bytes = bytes
    }
}

public struct SlowSensorSnapshot: Sendable {
    public var containerBytes: UInt64
    public var availableBytes: UInt64
    public var purgeableBytes: UInt64
    public var usedFraction: Double
    public var agentLabels: [String]
    public var brewPrefixes: [String]
    public var brewPathArch: String
    public var networkBytesPerSecond: Double
    public var identity: MachineIdentity

    public init(
        containerBytes: UInt64 = 0,
        availableBytes: UInt64 = 0,
        purgeableBytes: UInt64 = 0,
        usedFraction: Double = 0,
        agentLabels: [String] = [],
        brewPrefixes: [String] = [],
        brewPathArch: String = "unknown",
        networkBytesPerSecond: Double = 0,
        identity: MachineIdentity = .thisMacSeed
    ) {
        self.containerBytes = containerBytes
        self.availableBytes = availableBytes
        self.purgeableBytes = purgeableBytes
        self.usedFraction = usedFraction
        self.agentLabels = agentLabels
        self.brewPrefixes = brewPrefixes
        self.brewPathArch = brewPathArch
        self.networkBytesPerSecond = networkBytesPerSecond
        self.identity = identity
    }
}

public struct SlowSensors: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = ShellProcessRunner()) {
        self.runner = runner
    }

    public func read() -> SlowSensorSnapshot {
        var snap = SlowSensorSnapshot()
        snap.identity = readIdentity()
        let storage = readStorage()
        snap.containerBytes = storage.container
        snap.availableBytes = storage.available
        snap.purgeableBytes = storage.purgeable
        snap.usedFraction = storage.usedFraction
        snap.agentLabels = readLaunchAgents()
        let brew = readHomebrew()
        snap.brewPrefixes = brew.prefixes
        snap.brewPathArch = brew.arch
        snap.networkBytesPerSecond = readNetworkRate()
        return snap
    }

    public func sampleBundle(from snap: SlowSensorSnapshot, timestamp: Date = Date()) -> SampleBundle {
        var storage = Sample(domain: .storage, timestamp: timestamp)
        storage.set(.storageContainerBytes, Double(snap.containerBytes))
        storage.set(.storageAvailableBytes, Double(snap.availableBytes))
        storage.set(.storagePurgeableBytes, Double(snap.purgeableBytes))
        storage.set(.storageUsedFraction, snap.usedFraction)

        var background = Sample(domain: .background, timestamp: timestamp)
        background.set(.backgroundUserAgentCount, snap.agentLabels.count)
        background.set(.backgroundAgentLabels, snap.agentLabels.joined(separator: ","))

        var software = Sample(domain: .software, timestamp: timestamp)
        software.set(.softwareBrewPrefixes, snap.brewPrefixes.joined(separator: ","))
        software.set(.softwareBrewPathArch, snap.brewPathArch)

        var network = Sample(domain: .network, timestamp: timestamp)
        network.set(.networkBytesPerSecond, snap.networkBytesPerSecond)

        var compute = Sample(domain: .compute, timestamp: timestamp)
        compute.set(.machineName, snap.identity.name)
        compute.set(.machineModel, snap.identity.modelIdentifier)
        compute.set(.machineChip, snap.identity.chip)
        compute.set(.machineGPUCores, snap.identity.gpuCores)
        compute.set(.machineMemoryBytes, Double(snap.identity.memoryBytes))
        compute.set(.machineOSVersion, snap.identity.osVersion)
        compute.set(.machineSIP, snap.identity.sipEnabled)
        compute.set(.cpuPerformanceCores, snap.identity.performanceCores)
        compute.set(.cpuEfficiencyCores, snap.identity.efficiencyCores)

        return SampleBundle(timestamp: timestamp, samples: [storage, background, software, network, compute])
    }

    public struct FolderScanResult: Sendable {
        public var entries: [LargeFolderEntry]
        public var accessDenied: Bool
        public var storage: StorageScanResult
    }

    public func scanLargeFolders(limit: Int = 36) -> [LargeFolderEntry] {
        scanLargeFoldersDetailed(availableBytes: 0, limit: limit).entries
    }

    public func scanLargeFoldersDetailed(availableBytes: UInt64 = 0, limit: Int = 36) -> FolderScanResult {
        let storage = StorageScanner().scan(availableBytes: availableBytes, limit: limit)
        let entries = storage.candidates.map { LargeFolderEntry(path: $0.path, bytes: $0.bytes) }
        return FolderScanResult(entries: entries, accessDenied: storage.accessDenied, storage: storage)
    }

    private func readStorage() -> (container: UInt64, available: UInt64, purgeable: UInt64, usedFraction: Double) {
        let path = "/System/Volumes/Data"
        do {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeAvailableCapacityKey
            ])
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0))
            let opportunistic = UInt64(values.volumeAvailableCapacityForOpportunisticUsage ?? 0)
            let purgeable = opportunistic > available ? opportunistic - available : 0
            let usedFraction = total == 0 ? 0 : 1.0 - (Double(available) / Double(total))
            return (total, available, purgeable, usedFraction)
        } catch {
            return (0, 0, 0, 0)
        }
    }

    private func readLaunchAgents() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/LaunchAgents")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files
            .filter { $0.hasSuffix(".plist") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
    }

    private func readHomebrew() -> (prefixes: [String], arch: String) {
        var prefixes: [String] = []
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            prefixes.append("/opt/homebrew")
        }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            prefixes.append("/usr/local")
        }
        // Do NOT use this process's PATH — the GUI app keeps the PATH from launch,
        // so a ~/.zprofile fix would look like it "did nothing". Prefer zprofile, then a login shell.
        var arch = "unknown"
        if zprofilePrefersNativeHomebrew() {
            arch = "arm64"
        } else if let which = try? runner.run("/bin/zsh", arguments: ["-lc", "command -v brew"]),
                  let path = which.split(whereSeparator: \.isNewline).first.map(String.init) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("/opt/homebrew") {
                arch = "arm64"
            } else if trimmed.contains("/usr/local") {
                arch = "x86_64"
            }
        } else if prefixes.contains("/usr/local") {
            arch = "x86_64"
        } else if prefixes.contains("/opt/homebrew") {
            arch = "arm64"
        }
        return (prefixes, arch)
    }

    private func zprofilePrefersNativeHomebrew() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zprofile")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("/opt/homebrew/bin") || text.contains("PCOptopus native Homebrew")
    }

    private func readNetworkRate() -> Double {
        // Coarse: parse netstat -ib cumulative counters; rate needs delta — return 0 for single shot.
        // Autopilot loop will compute deltas.
        0
    }

    private func readIdentity() -> MachineIdentity {
        var identity = MachineIdentity.thisMacSeed
        identity.memoryBytes = ProcessInfo.processInfo.physicalMemory
        let ver = ProcessInfo.processInfo.operatingSystemVersion
        identity.osVersion = "\(ver.majorVersion).\(ver.minorVersion)"
        if let model = sysctlString("hw.model") {
            identity.modelIdentifier = model
        }
        if let brand = sysctlString("machdep.cpu.brand_string"), !brand.isEmpty {
            identity.chip = brand
        }
        identity.performanceCores = sysctlInt("hw.perflevel0.physicalcpu") ?? identity.performanceCores
        identity.efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu") ?? identity.efficiencyCores
        if let sip = try? runner.run("/usr/bin/csrutil", arguments: ["status"]) {
            identity.sipEnabled = sip.lowercased().contains("enabled")
        }
        identity.architecture = {
            #if arch(arm64)
            return "arm64"
            #else
            return "x86_64"
            #endif
        }()
        // GPU cores via system_profiler is slow — keep seed unless we already know.
        if let name = Host.current().localizedName {
            identity.name = name
        }
        return identity
    }
}

func sysctlString(_ name: String) -> String? {
    var size: size_t = 0
    sysctlbyname(name, nil, &size, nil, 0)
    guard size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

public enum FixtureLoader {
    public static func loadThisMacJSON(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw SensorError.parseFailed("fixture root")
        }
        return dict
    }

    public static func sampleBundle(fromFixture dict: [String: Any]) -> SampleBundle {
        let timestamp = Date()
        var samples: [Sample] = []

        if let storage = dict["storage"] as? [String: Any] {
            var s = Sample(domain: .storage, timestamp: timestamp)
            if let v = storage["containerBytes"] as? NSNumber { s.set(.storageContainerBytes, v.doubleValue) }
            if let v = storage["availableBytes"] as? NSNumber { s.set(.storageAvailableBytes, v.doubleValue) }
            if let v = storage["purgeableBytes"] as? NSNumber { s.set(.storagePurgeableBytes, v.doubleValue) }
            if let v = storage["usedFraction"] as? NSNumber { s.set(.storageUsedFraction, v.doubleValue) }
            samples.append(s)
        }

        if let memory = dict["memory"] as? [String: Any] {
            var s = Sample(domain: .memory, timestamp: timestamp)
            if let v = memory["pressure"] as? String { s.set(.memoryPressure, v) }
            if let v = memory["physicalBytes"] as? NSNumber { s.set(.memoryPhysicalBytes, v.doubleValue) }
            if let v = memory["compressorBytes"] as? NSNumber { s.set(.memoryCompressorBytes, v.doubleValue) }
            if let v = memory["swapBytes"] as? NSNumber { s.set(.memorySwapBytes, v.doubleValue) }
            samples.append(s)
        }

        if let energy = dict["energy"] as? [String: Any],
           let pmset = dict["pmsetCustom"] as? [String: Any] {
            var s = Sample(domain: .energy, timestamp: timestamp)
            if let v = energy["powerSource"] as? String { s.set(.energyPowerSource, v) }
            if let v = energy["thermalState"] as? String { s.set(.energyThermalState, v) }
            if let v = energy["lowPowerMode"] as? Bool { s.set(.energyLowPowerMode, v) }
            if let v = energy["assertionsPreventSleep"] as? Bool { s.set(.energyAssertionsPreventSleep, v) }
            if let ac = pmset["AC Power"] as? [String: Any] {
                if let v = ac["sleep"] as? NSNumber { s.set(.energyACSleepMinutes, v.intValue) }
                if let v = ac["displaysleep"] as? NSNumber { s.set(.energyACDisplaySleepMinutes, v.intValue) }
            }
            if let bat = pmset["Battery Power"] as? [String: Any] {
                if let v = bat["sleep"] as? NSNumber { s.set(.energyBatterySleepMinutes, v.intValue) }
                if let v = bat["displaysleep"] as? NSNumber { s.set(.energyBatteryDisplaySleepMinutes, v.intValue) }
            }
            samples.append(s)
        }

        if let background = dict["background"] as? [String: Any],
           let labels = background["userAgentLabels"] as? [String] {
            var s = Sample(domain: .background, timestamp: timestamp)
            s.set(.backgroundUserAgentCount, labels.count)
            s.set(.backgroundAgentLabels, labels.joined(separator: ","))
            samples.append(s)
        }

        if let software = dict["software"] as? [String: Any] {
            var s = Sample(domain: .software, timestamp: timestamp)
            if let prefixes = software["brewPrefixes"] as? [String] {
                s.set(.softwareBrewPrefixes, prefixes.joined(separator: ","))
            }
            if let arch = software["brewPathArch"] as? String {
                s.set(.softwareBrewPathArch, arch)
            }
            samples.append(s)
        }

        if let identity = dict["identity"] as? [String: Any] {
            var s = Sample(domain: .compute, timestamp: timestamp)
            if let v = identity["performanceCores"] as? NSNumber { s.set(.cpuPerformanceCores, v.intValue) }
            if let v = identity["efficiencyCores"] as? NSNumber { s.set(.cpuEfficiencyCores, v.intValue) }
            if let v = identity["name"] as? String { s.set(.machineName, v) }
            if let v = identity["modelIdentifier"] as? String { s.set(.machineModel, v) }
            if let v = identity["chip"] as? String { s.set(.machineChip, v) }
            if let v = identity["gpuCores"] as? NSNumber { s.set(.machineGPUCores, v.intValue) }
            if let v = identity["memoryBytes"] as? NSNumber { s.set(.machineMemoryBytes, v.doubleValue) }
            if let v = identity["osVersion"] as? String { s.set(.machineOSVersion, v) }
            if let v = identity["sipEnabled"] as? Bool { s.set(.machineSIP, v) }
            samples.append(s)
        }

        return SampleBundle(timestamp: timestamp, samples: samples)
    }
}
