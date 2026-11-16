import Foundation
import Model
import Store

public struct PolicyDecision: Sendable, Hashable {
    public var actionID: String
    public var beforeValue: String
    public var afterValue: String
    public var parameters: [String: String]
    public var reason: String

    public init(
        actionID: String,
        beforeValue: String,
        afterValue: String,
        parameters: [String: String] = [:],
        reason: String
    ) {
        self.actionID = actionID
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.parameters = parameters
        self.reason = reason
    }
}

public struct PolicyTickResult: Sendable {
    public var findings: [Finding]
    public var decisions: [PolicyDecision]
    public var autopilotStatus: AutopilotStatus
    public var activeProfile: WorkProfile

    public init(
        findings: [Finding],
        decisions: [PolicyDecision],
        autopilotStatus: AutopilotStatus,
        activeProfile: WorkProfile
    ) {
        self.findings = findings
        self.decisions = decisions
        self.autopilotStatus = autopilotStatus
        self.activeProfile = activeProfile
    }
}

public final class PolicyEngine: @unchecked Sendable {
    private let rules = RulePack()
    private var previousFindingIDs: [String: Int] = [:]
    private var lastApplyByAction: [String: Date] = [:]
    private var appliesThisHour: [(Date, String)] = []
    private let maxAppliesPerHour = 12
    private let cooldownMinutes: TimeInterval = 5 * 60
    /// Act on the first confirmed tick so Pulse can climb without waiting.
    private let requiredTicks = 1

    public init() {}

    public func evaluate(
        bundle: SampleBundle,
        contract: Contract,
        settings: AppSettings,
        now: Date = Date()
    ) -> PolicyTickResult {
        let raw = rules.evaluate(bundle, now: now)
        var findings: [Finding] = []
        for finding in raw {
            var f = finding
            let prior = previousFindingIDs[finding.id] ?? 0
            if finding.severity == .steady {
                f.consecutiveTicks = 1
                previousFindingIDs[finding.id] = 1
            } else {
                f.consecutiveTicks = prior + 1
                previousFindingIDs[finding.id] = f.consecutiveTicks
            }
            findings.append(f)
        }

        let profile = selectProfile(bundle: bundle)
        let status = resolveAutopilotStatus(bundle: bundle, contract: contract, settings: settings)
        var decisions: [PolicyDecision] = []

        if status == .on {
            decisions = makeAutopilotDecisions(
                findings: findings,
                bundle: bundle,
                contract: contract,
                now: now
            )
        }

        return PolicyTickResult(
            findings: findings,
            decisions: decisions,
            autopilotStatus: status,
            activeProfile: profile
        )
    }

    public func practices(from findings: [Finding], bundle: SampleBundle) -> [Practice] {
        var list = Practice.catalog
        for i in list.indices {
            switch list[i].id {
            case "storage.free80":
                let available = bundle.double(.storageAvailableBytes) ?? 0
                list[i].holding = available >= 80_000_000_000
                list[i].evidence = Formatters.bytes(available) + " available"
            case "energy.dockedSleep":
                let sleep = bundle.int(.energyACSleepMinutes) ?? 0
                list[i].holding = sleep == 0 || sleep >= 10
                list[i].evidence = "AC sleep \(Formatters.minutes(sleep))"
            case "background.knownHelpers":
                let labels = (bundle.string(.backgroundAgentLabels) ?? "").split(separator: ",").map(String.init)
                let unknown = labels.filter { label in
                    !AgentLabelInfo.known.contains(where: { $0.label == label })
                }
                list[i].holding = unknown.isEmpty
                list[i].evidence = "\(labels.count) agents, \(unknown.count) unrecognized"
            case "software.nativeBrew":
                let arch = bundle.string(.softwareBrewPathArch) ?? "unknown"
                list[i].holding = arch == "arm64"
                list[i].evidence = "brew arch \(arch)"
            default:
                break
            }
        }
        return list
    }

    private func selectProfile(bundle: SampleBundle) -> WorkProfile {
        let source = bundle.string(.energyPowerSource)
        if source == PowerSourceValue.ac.rawValue {
            return .docked
        }
        return .battery
    }

    private func resolveAutopilotStatus(
        bundle: SampleBundle,
        contract: Contract,
        settings: AppSettings
    ) -> AutopilotStatus {
        if settings.killSwitch { return .stopped }
        if !settings.autopilotMasterEnabled { return .off }
        if contract.enabledCount == 0 { return .off }

        let thermal = bundle.string(.energyThermalState)
        if thermal == ThermalStateValue.serious.rawValue
            || thermal == ThermalStateValue.critical.rawValue {
            return .paused
        }
        let prevent = bundle.bool(.energyAssertionsPreventSleep) ?? false
        if settings.pauseDuringPreventSleepAssertions && prevent {
            return .paused
        }
        if settings.pauseOnBattery && bundle.string(.energyPowerSource) == PowerSourceValue.battery.rawValue {
            return .paused
        }
        if let start = settings.quietHoursStart, let end = settings.quietHoursEnd {
            let hour = Calendar.current.component(.hour, from: Date())
            let inQuiet: Bool
            if start <= end {
                inQuiet = hour >= start && hour < end
            } else {
                inQuiet = hour >= start || hour < end
            }
            if inQuiet { return .paused }
        }
        return .on
    }

    private func makeAutopilotDecisions(
        findings: [Finding],
        bundle: SampleBundle,
        contract: Contract,
        now: Date
    ) -> [PolicyDecision] {
        appliesThisHour.removeAll { now.timeIntervalSince($0.0) > 3600 }
        var decisions: [PolicyDecision] = []

        for finding in findings {
            guard finding.severity >= .attention,
                  finding.consecutiveTicks >= requiredTicks else { continue }
            for actionID in finding.actionIDs {
                guard let grant = contract.grant(for: actionID), grant.enabled else { continue }
                guard ActionCatalog.definition(id: actionID)?.risk == .autopilot else { continue }
                if let last = lastApplyByAction[actionID],
                   now.timeIntervalSince(last) < cooldownMinutes {
                    continue
                }
                if appliesThisHour.count >= maxAppliesPerHour { break }

                if let decision = decisionFor(
                    actionID: actionID,
                    grant: grant,
                    bundle: bundle,
                    finding: finding
                ) {
                    decisions.append(decision)
                    lastApplyByAction[actionID] = now
                    appliesThisHour.append((now, actionID))
                }
            }
        }
        return decisions
    }

    private func decisionFor(
        actionID: String,
        grant: ContractGrant,
        bundle: SampleBundle,
        finding: Finding
    ) -> PolicyDecision? {
        switch actionID {
        case "energy.ac.sleep.set":
            let current = bundle.int(.energyACSleepMinutes) ?? 0
            let target = Int(grant.bounds.target ?? 30)
            let minV = Int(grant.bounds.min ?? 10)
            let maxV = Int(grant.bounds.max ?? 60)
            let clamped = min(max(target, minV), maxV)
            guard current != clamped else { return nil }
            // Only act when current is outside the healthy band for docked work
            guard current > 0 && current < minV else { return nil }
            return PolicyDecision(
                actionID: actionID,
                beforeValue: String(current),
                afterValue: String(clamped),
                parameters: [
                    "key": "sleep",
                    "powerSource": "AC",
                    "value": String(clamped)
                ],
                reason: finding.summary
            )
        case "energy.ac.displaysleep.set":
            let current = bundle.int(.energyACDisplaySleepMinutes) ?? 0
            let target = Int(grant.bounds.target ?? 10)
            let minV = Int(grant.bounds.min ?? 5)
            let maxV = Int(grant.bounds.max ?? 30)
            let clamped = min(max(target, minV), maxV)
            guard current != clamped else { return nil }
            return PolicyDecision(
                actionID: actionID,
                beforeValue: String(current),
                afterValue: String(clamped),
                parameters: [
                    "key": "displaysleep",
                    "powerSource": "AC",
                    "value": String(clamped)
                ],
                reason: finding.summary
            )
        case "energy.battery.sleep.set":
            let current = bundle.int(.energyBatterySleepMinutes) ?? 0
            let target = Int(grant.bounds.target ?? 15)
            let minV = Int(grant.bounds.min ?? 5)
            let maxV = Int(grant.bounds.max ?? 30)
            let clamped = min(max(target, minV), maxV)
            guard current > 0 && current < minV, current != clamped else { return nil }
            return PolicyDecision(
                actionID: actionID,
                beforeValue: String(current),
                afterValue: String(clamped),
                parameters: [
                    "key": "sleep",
                    "powerSource": "Battery",
                    "value": String(clamped)
                ],
                reason: finding.summary
            )
        case "background.agent.disable":
            guard let label = grant.bounds.agentLabel, !label.isEmpty else { return nil }
            let labels = (bundle.string(.backgroundAgentLabels) ?? "").split(separator: ",").map(String.init)
            guard labels.contains(label) else { return nil }
            return PolicyDecision(
                actionID: actionID,
                beforeValue: "loaded:\(label)",
                afterValue: "disabled:\(label)",
                parameters: ["label": label],
                reason: finding.summary
            )
        default:
            return nil
        }
    }
}
