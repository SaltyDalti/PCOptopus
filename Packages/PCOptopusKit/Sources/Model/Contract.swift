import Foundation

public struct ContractGrant: Codable, Sendable, Identifiable, Hashable {
    public var id: String { actionID }
    public var actionID: String
    public var enabled: Bool
    public var bounds: ActionBounds

    public init(actionID: String, enabled: Bool = false, bounds: ActionBounds = ActionBounds()) {
        self.actionID = actionID
        self.enabled = enabled
        self.bounds = bounds
    }
}

public struct Contract: Codable, Sendable, Hashable {
    public var grants: [ContractGrant]
    public var updatedAt: Date

    public init(grants: [ContractGrant] = [], updatedAt: Date = Date()) {
        self.grants = grants
        self.updatedAt = updatedAt
    }

    public static func emptyDefault() -> Contract {
        let grants = ActionCatalog.all
            .filter { $0.risk == .autopilot }
            .map { def in
                ContractGrant(
                    actionID: def.id,
                    enabled: false,
                    bounds: def.defaultBounds ?? ActionBounds()
                )
            }
        return Contract(grants: grants)
    }

    public func grant(for actionID: String) -> ContractGrant? {
        grants.first { $0.actionID == actionID }
    }

    public func isGranted(_ actionID: String) -> Bool {
        grant(for: actionID)?.enabled == true
    }

    public mutating func setEnabled(_ actionID: String, enabled: Bool) {
        if let idx = grants.firstIndex(where: { $0.actionID == actionID }) {
            grants[idx].enabled = enabled
        } else if let def = ActionCatalog.definition(id: actionID) {
            grants.append(ContractGrant(
                actionID: actionID,
                enabled: enabled,
                bounds: def.defaultBounds ?? ActionBounds()
            ))
        }
        updatedAt = Date()
    }

    public mutating func setBounds(_ actionID: String, bounds: ActionBounds) {
        if let idx = grants.firstIndex(where: { $0.actionID == actionID }) {
            grants[idx].bounds = bounds
        }
        updatedAt = Date()
    }

    public var enabledCount: Int {
        grants.filter(\.enabled).count
    }
}
