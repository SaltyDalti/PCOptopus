import Foundation

public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case steady
    case attention
    case act

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .steady: return 0
        case .attention: return 1
        case .act: return 2
        }
    }

    public var title: String {
        switch self {
        case .steady: return "Steady"
        case .attention: return "Attention"
        case .act: return "Act"
        }
    }
}

public struct Finding: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var domain: Domain
    public var severity: Severity
    public var title: String
    public var summary: String
    public var evidence: [String]
    public var actionIDs: [String]
    public var firstSeen: Date
    public var lastSeen: Date
    public var consecutiveTicks: Int

    public init(
        id: String,
        domain: Domain,
        severity: Severity,
        title: String,
        summary: String,
        evidence: [String] = [],
        actionIDs: [String] = [],
        firstSeen: Date = Date(),
        lastSeen: Date = Date(),
        consecutiveTicks: Int = 1
    ) {
        self.id = id
        self.domain = domain
        self.severity = severity
        self.title = title
        self.summary = summary
        self.evidence = evidence
        self.actionIDs = actionIDs
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.consecutiveTicks = consecutiveTicks
    }
}
