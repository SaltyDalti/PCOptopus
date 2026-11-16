import Foundation

public enum JournalActor: String, Codable, Sendable {
    case you
    case autopilot
}

public enum JournalResult: String, Codable, Sendable {
    case pending
    case applied
    case failed
    case undone
}

public struct JournalEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var actor: JournalActor
    public var actionID: String
    public var title: String
    public var beforeValue: String
    public var afterValue: String
    public var result: JournalResult
    public var errorMessage: String?
    public var rollbackPayload: String
    public var domain: Domain

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actor: JournalActor,
        actionID: String,
        title: String,
        beforeValue: String,
        afterValue: String,
        result: JournalResult = .pending,
        errorMessage: String? = nil,
        rollbackPayload: String,
        domain: Domain
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.actionID = actionID
        self.title = title
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.result = result
        self.errorMessage = errorMessage
        self.rollbackPayload = rollbackPayload
        self.domain = domain
    }
}

public struct PendingApply: Codable, Sendable, Hashable {
    public var actionID: String
    public var actor: JournalActor
    public var beforeValue: String
    public var afterValue: String
    public var rollbackPayload: String
    public var parameters: [String: String]

    public init(
        actionID: String,
        actor: JournalActor,
        beforeValue: String,
        afterValue: String,
        rollbackPayload: String,
        parameters: [String: String] = [:]
    ) {
        self.actionID = actionID
        self.actor = actor
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.rollbackPayload = rollbackPayload
        self.parameters = parameters
    }
}
