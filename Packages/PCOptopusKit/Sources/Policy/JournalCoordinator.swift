import Foundation
import Model
import Store
import Apply

public final class JournalCoordinator: @unchecked Sendable {
    private let store: SQLiteStore
    private let applier: any ActionApplying

    public init(store: SQLiteStore, applier: any ActionApplying) {
        self.store = store
        self.applier = applier
    }

    /// Write-ahead: insert pending, apply, mark applied/failed.
    @discardableResult
    public func apply(
        decision: PolicyDecision,
        actor: JournalActor,
        killSwitch: Bool
    ) throws -> JournalEntry {
        if killSwitch {
            throw ApplyError.killSwitchEngaged
        }
        let def = ActionCatalog.definition(id: decision.actionID)
        var entry = JournalEntry(
            actor: actor,
            actionID: decision.actionID,
            title: def?.title ?? decision.actionID,
            beforeValue: decision.beforeValue,
            afterValue: decision.afterValue,
            result: .pending,
            rollbackPayload: decision.beforeValue,
            domain: def?.domain ?? .energy
        )
        // Enrich rollback for agent disables
        if decision.actionID == "background.agent.disable",
           let label = decision.parameters["label"] {
            entry.rollbackPayload = label
        }
        if decision.actionID == "software.brew.path.native" {
            entry.rollbackPayload = decision.parameters["previousFile"] ?? decision.beforeValue
        }
        try store.insertJournal(entry)

        do {
            let result = try applier.apply(
                actionID: decision.actionID,
                parameters: decision.parameters,
                killSwitch: killSwitch
            )
            entry.result = .applied
            if let payload = result.rollbackPayload {
                entry.rollbackPayload = payload
            }
            try store.updateJournal(entry)
            return entry
        } catch {
            entry.result = .failed
            entry.errorMessage = error.localizedDescription
            try store.updateJournal(entry)
            throw error
        }
    }

    @discardableResult
    public func undo(entryID: UUID, killSwitch: Bool) throws -> JournalEntry {
        if killSwitch { throw ApplyError.killSwitchEngaged }
        var entry = try store.journalEntry(id: entryID)
        guard entry.result == .applied else {
            throw ApplyError.failed("Entry is not applied")
        }
        _ = try applier.rollback(
            actionID: entry.actionID,
            rollbackPayload: entry.rollbackPayload,
            parameters: undoParameters(for: entry),
            killSwitch: killSwitch
        )
        entry.result = .undone
        try store.updateJournal(entry)
        return entry
    }

    private func undoParameters(for entry: JournalEntry) -> [String: String] {
        switch entry.actionID {
        case "energy.ac.sleep.set":
            return ["key": "sleep", "powerSource": "AC", "value": entry.rollbackPayload]
        case "energy.ac.displaysleep.set":
            return ["key": "displaysleep", "powerSource": "AC", "value": entry.rollbackPayload]
        case "energy.battery.sleep.set":
            return ["key": "sleep", "powerSource": "Battery", "value": entry.rollbackPayload]
        case "background.agent.disable":
            return ["label": entry.rollbackPayload, "enable": "true"]
        case "software.brew.path.native":
            return ["restoreFile": entry.rollbackPayload]
        default:
            return ["value": entry.rollbackPayload]
        }
    }
}
