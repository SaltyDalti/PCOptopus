import Foundation
import Model
import Policy

public protocol Coaching: Sendable {
    func todayParagraph(findings: [Finding], bundle: SampleBundle, status: AutopilotStatus, pulse: PulseScore) -> String
    func answer(question: String, findings: [Finding], bundle: SampleBundle, pulse: PulseScore) -> CoachAnswer
    func weekSummary(practices: [Practice], autopilotCount: Int, pulse: PulseScore) -> String
}

public struct CoachAnswer: Sendable {
    public var prose: String
    public var actionIDs: [String]

    public init(prose: String, actionIDs: [String] = []) {
        self.prose = prose
        self.actionIDs = actionIDs
    }
}

/// Template coach — ships without Apple Intelligence. Foundation Models adapter wraps this protocol.
public struct TemplateCoach: Coaching {
    public init() {}

    public func todayParagraph(findings: [Finding], bundle: SampleBundle, status: AutopilotStatus, pulse: PulseScore) -> String {
        let lead = findings
            .filter { $0.severity >= .attention }
            .sorted { $0.severity > $1.severity }
            .first
        let available = bundle.double(.storageAvailableBytes).map { Formatters.bytes($0) } ?? "—"
        let pressure = bundle.string(.memoryPressure) ?? "—"

        if pulse.percent >= 100 {
            return "One goal: Pulse 100 — holding. Autopilot is \(status.title.lowercased()) and will fight any slip. Storage \(available) free; memory \(pressure)."
        }
        if let lead {
            return "One goal: Pulse 100. Down \(pulse.deficit) — \(lead.title). Autopilot is \(status == .on ? "fighting" : "arming") every safe fix. Memory \(pressure); storage \(available) free."
        }
        return "One goal: Pulse 100. Down \(pulse.deficit). Autopilot is \(status.title.lowercased()). Memory \(pressure); storage \(available) free."
    }

    public func answer(question: String, findings: [Finding], bundle: SampleBundle, pulse: PulseScore) -> CoachAnswer {
        let q = question.lowercased()
        let actionIDs = findings.flatMap(\.actionIDs)
        if q.contains("pulse") || q.contains("health") || q.contains("score") {
            let drag = pulse.primaryDragTitle.map { " Biggest drag: \($0)." } ?? ""
            return CoachAnswer(
                prose: "\(pulse.headline). Band: \(pulse.band.title).\(drag) Every Fix and Autopilot change is aimed at reclaiming those points.",
                actionIDs: Array(actionIDs.prefix(3))
            )
        }
        if q.contains("sleep") || q.contains("pmset") {
            let sleep = bundle.int(.energyACSleepMinutes).map { Formatters.minutes($0) } ?? "unknown"
            return CoachAnswer(
                prose: "AC system sleep is \(sleep). A docked grant around 30 minutes keeps sessions alive while plugged in — that lifts Pulse when sleep is the drag. `hibernatemode` is shown and left alone.",
                actionIDs: actionIDs.filter { $0.contains("sleep") }
            )
        }
        if q.contains("storage") || q.contains("disk") || q.contains("space") {
            let available = bundle.double(.storageAvailableBytes).map { Formatters.bytes($0) } ?? "—"
            let total = bundle.double(.storageContainerBytes).map { Formatters.bytes($0) } ?? "—"
            return CoachAnswer(
                prose: "\(available) available of \(total). Aim for at least 80 GB free — storage is often the main Pulse drag. Show me scans the Mac for old/unused/regenerable files first and recommends what to delete; PCOptopus never deletes for you.",
                actionIDs: actionIDs.filter { $0.contains("storage") }
            )
        }
        if q.contains("brew") || q.contains("homebrew") || q.contains("rosetta") {
            let arch = bundle.string(.softwareBrewPathArch) ?? "unknown"
            return CoachAnswer(
                prose: "The first brew on PATH reports architecture \(arch). Prefer `/opt/homebrew` on Apple silicon. Fixing PATH reclaims Pulse points; bottle migration stays manual.",
                actionIDs: actionIDs.filter { $0.contains("brew") }
            )
        }
        if q.contains("memory") || q.contains("ram") {
            let pressure = bundle.string(.memoryPressure) ?? "—"
            return CoachAnswer(
                prose: "Memory pressure is \(pressure). Unified memory is shared with the GPU; there is no free-RAM action because emptying RAM is wasted work on this chip.",
                actionIDs: []
            )
        }
        let lead = findings.sorted { $0.severity > $1.severity }.first
        return CoachAnswer(
            prose: lead.map { "Pulse \(pulse.percent). \($0.summary)" }
                ?? "Pulse \(pulse.percent). Ask about pulse, storage, sleep, Homebrew, or memory.",
            actionIDs: Array(actionIDs.prefix(3))
        )
    }

    public func weekSummary(practices: [Practice], autopilotCount: Int, pulse: PulseScore) -> String {
        let holding = practices.filter(\.holding).count
        let slip = practices.filter { !$0.holding }.first
        var text = "Pulse \(pulse.percent). \(holding) of \(practices.count) practices holding. Autopilot fought \(autopilotCount) time\(autopilotCount == 1 ? "" : "s") this week."
        if let slip {
            text += " Next focus: \(slip.title)."
        }
        return text
    }
}

/// Placeholder for Apple Foundation Models when available on the deployment OS.
public struct FoundationModelsCoach: Coaching {
    private let fallback: TemplateCoach

    public init(fallback: TemplateCoach = TemplateCoach()) {
        self.fallback = fallback
    }

    public func todayParagraph(findings: [Finding], bundle: SampleBundle, status: AutopilotStatus, pulse: PulseScore) -> String {
        // Foundation Models require macOS 26+ SDK availability; template always works.
        fallback.todayParagraph(findings: findings, bundle: bundle, status: status, pulse: pulse)
    }

    public func answer(question: String, findings: [Finding], bundle: SampleBundle, pulse: PulseScore) -> CoachAnswer {
        fallback.answer(question: question, findings: findings, bundle: bundle, pulse: pulse)
    }

    public func weekSummary(practices: [Practice], autopilotCount: Int, pulse: PulseScore) -> String {
        fallback.weekSummary(practices: practices, autopilotCount: autopilotCount, pulse: pulse)
    }
}
