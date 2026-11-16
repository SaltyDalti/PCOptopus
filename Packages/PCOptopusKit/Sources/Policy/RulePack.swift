import Foundation
import Model

public struct RulePack: Sendable {
    public init() {}

    public func evaluate(_ bundle: SampleBundle, now: Date = Date()) -> [Finding] {
        var findings: [Finding] = []
        findings.append(contentsOf: storage(bundle, now: now))
        findings.append(contentsOf: dockedSleep(bundle, now: now))
        findings.append(contentsOf: batterySleep(bundle, now: now))
        findings.append(contentsOf: memory(bundle, now: now))
        findings.append(contentsOf: assertions(bundle, now: now))
        findings.append(contentsOf: background(bundle, now: now))
        findings.append(contentsOf: brew(bundle, now: now))
        findings.append(contentsOf: thermal(bundle, now: now))
        return findings
    }

    private func storage(_ bundle: SampleBundle, now: Date) -> [Finding] {
        guard let available = bundle.double(.storageAvailableBytes),
              let total = bundle.double(.storageContainerBytes) else { return [] }
        let availableU = UInt64(available)
        let totalU = UInt64(total)
        let freeFraction = total == 0 ? 1 : available / total
        let evidence = [
            Formatters.availableOfTotal(available: availableU, total: totalU),
            "Purgeable space is separate from available — macOS may reclaim it under pressure."
        ]
        if available < 40_000_000_000 {
            return [Finding(
                id: "storage.room",
                domain: .storage,
                severity: .act,
                title: "Storage is critically low",
                summary: "\(Formatters.bytes(availableU)) available of \(Formatters.bytes(totalU)). Updates and sleep images need headroom.",
                evidence: evidence,
                actionIDs: ["storage.scan.largeFolders"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        if available < 80_000_000_000 || freeFraction < 0.15 {
            return [Finding(
                id: "storage.room",
                domain: .storage,
                severity: .attention,
                title: "Storage room is tight",
                summary: "\(Formatters.bytes(availableU)) available of \(Formatters.bytes(totalU)). Aim for at least 80 GB free.",
                evidence: evidence,
                actionIDs: ["storage.scan.largeFolders"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "storage.room",
            domain: .storage,
            severity: .steady,
            title: "Storage has headroom",
            summary: "\(Formatters.bytes(availableU)) available of \(Formatters.bytes(totalU)).",
            evidence: evidence,
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func dockedSleep(_ bundle: SampleBundle, now: Date) -> [Finding] {
        guard let sleep = bundle.int(.energyACSleepMinutes) else { return [] }
        let display = bundle.int(.energyACDisplaySleepMinutes)
        let evidence: [String] = [
            "AC system sleep is \(Formatters.minutes(sleep)).",
            display.map { "AC display sleep is \(Formatters.minutes($0))." } ?? "AC display sleep unknown."
        ]
        if sleep > 0 && sleep < 10 {
            return [Finding(
                id: "energy.dockedSleep",
                domain: .energy,
                severity: .act,
                title: "Plugged-in sleep is too short",
                summary: "On AC, system sleep is \(Formatters.minutes(sleep)), so sessions and downloads suspend before the display timer matters. A docked grant of about 30 minutes keeps this Mac usable while plugged in.",
                evidence: evidence,
                actionIDs: ["energy.ac.sleep.set"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "energy.dockedSleep",
            domain: .energy,
            severity: .steady,
            title: "Plugged-in sleep matches work",
            summary: "AC system sleep is \(Formatters.minutes(sleep)).",
            evidence: evidence,
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func batterySleep(_ bundle: SampleBundle, now: Date) -> [Finding] {
        guard let sleep = bundle.int(.energyBatterySleepMinutes) else { return [] }
        if sleep > 0 && sleep < 5 {
            return [Finding(
                id: "energy.batterySleep",
                domain: .energy,
                severity: .attention,
                title: "Battery sleep is very short",
                summary: "On battery, system sleep is \(Formatters.minutes(sleep)). A short pause is fine; raising it toward never drains the pack.",
                evidence: ["Battery system sleep is \(Formatters.minutes(sleep))."],
                actionIDs: ["energy.battery.sleep.set"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "energy.batterySleep",
            domain: .energy,
            severity: .steady,
            title: "Battery sleep is sane",
            summary: "Battery system sleep is \(Formatters.minutes(sleep)).",
            evidence: ["Battery system sleep is \(Formatters.minutes(sleep))."],
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func memory(_ bundle: SampleBundle, now: Date) -> [Finding] {
        let pressure = bundle.string(.memoryPressure) ?? MemoryPressureValue.unknown.rawValue
        let swap = bundle.double(.memorySwapBytes) ?? 0
        let physical = bundle.double(.memoryPhysicalBytes) ?? Double(MachineIdentity.thisMacSeed.memoryBytes)
        let evidence = [
            "Memory pressure: \(pressure).",
            "Swap in use: \(Formatters.bytes(swap)).",
            "Physical: \(Formatters.bytes(physical)) unified."
        ]
        if pressure == MemoryPressureValue.warning.rawValue
            || pressure == MemoryPressureValue.critical.rawValue
            || swap > 1_000_000_000 {
            return [Finding(
                id: "memory.pressure",
                domain: .memory,
                severity: .attention,
                title: "Memory pressure is elevated",
                summary: "Pressure is \(pressure). On Apple silicon, CPU and GPU share unified memory — emptying RAM is wasted work. Close heavy apps if this persists.",
                evidence: evidence,
                actionIDs: [],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "memory.pressure",
            domain: .memory,
            severity: .steady,
            title: "Memory pressure is normal",
            summary: "Pressure is \(pressure); compressor may still work. Unified memory stays healthy when swap stays flat.",
            evidence: evidence,
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func assertions(_ bundle: SampleBundle, now: Date) -> [Finding] {
        let prevent = bundle.bool(.energyAssertionsPreventSleep) ?? false
        let minutes = bundle.double(.energyAssertionMinutes) ?? 0
        let name = bundle.string(.energyAssertionProcess) ?? "an app"
        guard prevent, minutes >= 45 else {
            return [Finding(
                id: "energy.assertion",
                domain: .energy,
                severity: .steady,
                title: "No long sleep assertion",
                summary: "Nothing is holding PreventUserIdleSystemSleep for a long stretch.",
                evidence: [],
                actionIDs: [],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "energy.assertion",
            domain: .energy,
            severity: .attention,
            title: "\(name) is keeping the Mac awake",
            summary: "\(name) has held PreventUserIdleSystemSleep for about \(Int(minutes)) minutes. Autopilot pauses while this assertion holds.",
            evidence: ["Process: \(name)", "Held about \(Int(minutes)) minutes"],
            actionIDs: ["energy.assertion.quitApp"],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func background(_ bundle: SampleBundle, now: Date) -> [Finding] {
        let labels = (bundle.string(.backgroundAgentLabels) ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !labels.isEmpty else { return [] }
        let suggested = labels.filter { AgentLabelInfo.info(for: $0).suggestedDisable }
        let evidence = labels.map { label in
            let info = AgentLabelInfo.info(for: label)
            return "\(label) — \(info.summary)"
        }
        if !suggested.isEmpty {
            return [Finding(
                id: "background.agents",
                domain: .background,
                severity: .attention,
                title: "Heavy background helpers are loaded",
                summary: "\(labels.count) user LaunchAgents are present. \(suggested.count) look expensive (for example BlueStacks). Grant a disable only for labels you recognize.",
                evidence: evidence,
                actionIDs: ["background.agent.disable"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "background.agents",
            domain: .background,
            severity: .steady,
            title: "Login helpers are inventoried",
            summary: "\(labels.count) user LaunchAgents are present. Review any you do not recognize.",
            evidence: evidence,
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func brew(_ bundle: SampleBundle, now: Date) -> [Finding] {
        let arch = bundle.string(.softwareBrewPathArch) ?? "unknown"
        let prefixes = bundle.string(.softwareBrewPrefixes) ?? ""
        let hasNative = prefixes.contains("/opt/homebrew")
        if arch == "x86_64" && hasNative {
            return [Finding(
                id: "software.brew.arch",
                domain: .software,
                severity: .act,
                title: "PATH prefers Rosetta Homebrew",
                summary: "The first `brew` on PATH is x86_64 while `/opt/homebrew` exists. Prefer the native prefix so tools skip Rosetta.",
                evidence: [
                    "brew PATH architecture: \(arch)",
                    "Prefixes: \(prefixes)"
                ],
                actionIDs: ["software.brew.path.native"],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "software.brew.arch",
            domain: .software,
            severity: .steady,
            title: "Homebrew architecture looks native",
            summary: "brew PATH architecture: \(arch).",
            evidence: ["Prefixes: \(prefixes)"],
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }

    private func thermal(_ bundle: SampleBundle, now: Date) -> [Finding] {
        let state = bundle.string(.energyThermalState) ?? ThermalStateValue.nominal.rawValue
        if state == ThermalStateValue.serious.rawValue || state == ThermalStateValue.critical.rawValue {
            return [Finding(
                id: "energy.thermal",
                domain: .energy,
                severity: .act,
                title: "Thermal pressure is high",
                summary: "Thermal state is \(state). Autopilot pauses. Give the chassis air; no fan or GPU pmset knobs exist on this Mac.",
                evidence: ["Thermal state: \(state)"],
                actionIDs: [],
                firstSeen: now,
                lastSeen: now
            )]
        }
        return [Finding(
            id: "energy.thermal",
            domain: .energy,
            severity: .steady,
            title: "Thermals are calm",
            summary: "Thermal state is \(state).",
            evidence: ["Thermal state: \(state)"],
            actionIDs: [],
            firstSeen: now,
            lastSeen: now
        )]
    }
}
