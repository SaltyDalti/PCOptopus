import Foundation
import Model

public enum ApplyError: Error, LocalizedError, Sendable {
    case killSwitchEngaged
    case unknownAction(String)
    case refusedKey(String)
    case failed(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .killSwitchEngaged: return "Kill switch is on — no changes will run."
        case .unknownAction(let id): return "Unknown action: \(id)"
        case .refusedKey(let key): return "Helper refused key: \(key)"
        case .failed(let message): return message
        case .notImplemented(let message): return message
        }
    }
}

public struct ApplyResult: Sendable {
    public var rollbackPayload: String?

    public init(rollbackPayload: String? = nil) {
        self.rollbackPayload = rollbackPayload
    }
}

public protocol ActionApplying: Sendable {
    func apply(
        actionID: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult

    func rollback(
        actionID: String,
        rollbackPayload: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult
}

/// Records applies without touching the system — for policy and journal tests.
public final class FakeApplier: ActionApplying, @unchecked Sendable {
    public private(set) var applied: [(String, [String: String])] = []
    public private(set) var rolledBack: [(String, String)] = []
    public var shouldFail = false

    public init() {}

    public func apply(
        actionID: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        if shouldFail { throw ApplyError.failed("fake failure") }
        applied.append((actionID, parameters))
        return ApplyResult(rollbackPayload: parameters["value"] ?? parameters["label"])
    }

    public func rollback(
        actionID: String,
        rollbackPayload: String,
        parameters: [String: String],
        killSwitch: Bool
    ) throws -> ApplyResult {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        rolledBack.append((actionID, rollbackPayload))
        return ApplyResult()
    }
}
