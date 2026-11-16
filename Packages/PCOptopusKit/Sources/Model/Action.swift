import Foundation

public enum ActionRisk: String, Codable, Sendable, CaseIterable {
    case autopilot
    case confirm
    case manual

    public var title: String {
        switch self {
        case .autopilot: return "Can run on its own"
        case .confirm: return "Asks you"
        case .manual: return "For you to do by hand"
        }
    }

    public var primaryButtonTitle: String {
        switch self {
        case .autopilot: return "Grant and allow"
        case .confirm: return "Apply once"
        case .manual: return "Show me how"
        }
    }
}

public struct ActionBounds: Codable, Sendable, Hashable {
    public var min: Double?
    public var max: Double?
    public var target: Double?
    public var powerSource: String?
    public var agentLabel: String?

    public init(
        min: Double? = nil,
        max: Double? = nil,
        target: Double? = nil,
        powerSource: String? = nil,
        agentLabel: String? = nil
    ) {
        self.min = min
        self.max = max
        self.target = target
        self.powerSource = powerSource
        self.agentLabel = agentLabel
    }
}

public struct ActionDefinition: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var domain: Domain
    public var risk: ActionRisk
    public var title: String
    public var detail: String
    public var settingKey: String?
    public var defaultBounds: ActionBounds?

    public init(
        id: String,
        domain: Domain,
        risk: ActionRisk,
        title: String,
        detail: String,
        settingKey: String? = nil,
        defaultBounds: ActionBounds? = nil
    ) {
        self.id = id
        self.domain = domain
        self.risk = risk
        self.title = title
        self.detail = detail
        self.settingKey = settingKey
        self.defaultBounds = defaultBounds
    }
}

public enum ActionCatalog {
    public static let all: [ActionDefinition] = [
        ActionDefinition(
            id: "energy.ac.sleep.set",
            domain: .energy,
            risk: .autopilot,
            title: "Set AC system sleep",
            detail: "Change `pmset -c sleep` within the bounds you grant.",
            settingKey: "sleep",
            defaultBounds: ActionBounds(min: 10, max: 60, target: 30, powerSource: "AC")
        ),
        ActionDefinition(
            id: "energy.ac.displaysleep.set",
            domain: .energy,
            risk: .autopilot,
            title: "Set AC display sleep",
            detail: "Change `pmset -c displaysleep` within the bounds you grant.",
            settingKey: "displaysleep",
            defaultBounds: ActionBounds(min: 5, max: 30, target: 10, powerSource: "AC")
        ),
        ActionDefinition(
            id: "energy.battery.sleep.set",
            domain: .energy,
            risk: .autopilot,
            title: "Set battery system sleep",
            detail: "Change `pmset -b sleep` within the bounds you grant.",
            settingKey: "sleep",
            defaultBounds: ActionBounds(min: 5, max: 30, target: 15, powerSource: "Battery")
        ),
        ActionDefinition(
            id: "background.agent.disable",
            domain: .background,
            risk: .autopilot,
            title: "Disable a user LaunchAgent",
            detail: "bootout a user LaunchAgent you named in the contract; plist is journaled first."
        ),
        ActionDefinition(
            id: "software.brew.path.native",
            domain: .software,
            risk: .confirm,
            title: "Prefer native Homebrew on PATH",
            detail: "Prepend `/opt/homebrew/bin` in `~/.zprofile` and keep the previous file for undo."
        ),
        ActionDefinition(
            id: "storage.scan.largeFolders",
            domain: .storage,
            risk: .manual,
            title: "Scan for reclaimable storage",
            detail: "Intelligently scan the Mac for old, unused, and regenerable files first, then recommend deletions to reach 80 GB free. Deletes nothing."
        ),
        ActionDefinition(
            id: "energy.assertion.quitApp",
            domain: .energy,
            risk: .confirm,
            title: "Quit app holding sleep assertion",
            detail: "Quit the named app that has held PreventUserIdleSystemSleep for a long time."
        ),
        ActionDefinition(
            id: "energy.lowPowerMode",
            domain: .energy,
            risk: .confirm,
            title: "Toggle Low Power Mode",
            detail: "Ask before changing Low Power Mode."
        )
    ]

    public static func definition(id: String) -> ActionDefinition? {
        all.first { $0.id == id }
    }
}
