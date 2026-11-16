import Foundation

public enum WorkProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    case docked
    case battery
    case deepWork

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .docked: return "Docked"
        case .battery: return "Battery"
        case .deepWork: return "Deep work"
        }
    }

    public var detail: String {
        switch self {
        case .docked:
            return "Plugged in: keep the machine awake long enough for sessions, downloads, and backups."
        case .battery:
            return "On battery: shorter sleep, still usable between meetings."
        case .deepWork:
            return "Fewer background helpers; energy settings stay within your grants."
        }
    }
}

public enum AutopilotStatus: String, Codable, Sendable {
    case off
    case on
    case paused
    case stopped

    public var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }
}

public struct AppSettings: Codable, Sendable, Hashable {
    public var killSwitch: Bool
    public var pauseOnBattery: Bool
    public var pauseDuringPreventSleepAssertions: Bool
    public var quietHoursStart: Int?
    public var quietHoursEnd: Int?
    public var hasCompletedOnboarding: Bool
    public var autopilotMasterEnabled: Bool

    public init(
        killSwitch: Bool = false,
        pauseOnBattery: Bool = false,
        pauseDuringPreventSleepAssertions: Bool = true,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        hasCompletedOnboarding: Bool = false,
        autopilotMasterEnabled: Bool = false
    ) {
        self.killSwitch = killSwitch
        self.pauseOnBattery = pauseOnBattery
        self.pauseDuringPreventSleepAssertions = pauseDuringPreventSleepAssertions
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.autopilotMasterEnabled = autopilotMasterEnabled
    }
}

public struct Practice: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var detail: String
    public var holding: Bool
    public var evidence: String

    public init(id: String, title: String, detail: String, holding: Bool, evidence: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.holding = holding
        self.evidence = evidence
    }

    public static let catalog: [Practice] = [
        Practice(
            id: "storage.free80",
            title: "Keep at least 80 GB free",
            detail: "Updates, caches, and sleep images need headroom on the Data volume.",
            holding: false,
            evidence: ""
        ),
        Practice(
            id: "energy.dockedSleep",
            title: "Plugged-in sleep matches the work",
            detail: "On AC, system sleep should sit around 15–60 minutes for a machine you rely on.",
            holding: false,
            evidence: ""
        ),
        Practice(
            id: "background.knownHelpers",
            title: "Recognize every login helper",
            detail: "If you cannot name it, it should not stay loaded by default.",
            holding: false,
            evidence: ""
        ),
        Practice(
            id: "software.nativeBrew",
            title: "Use the native Homebrew",
            detail: "Prefer `/opt/homebrew` on Apple silicon so tools skip Rosetta.",
            holding: false,
            evidence: ""
        )
    ]
}
