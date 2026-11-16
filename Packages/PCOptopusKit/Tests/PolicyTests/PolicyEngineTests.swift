import XCTest
@testable import Policy
@testable import Model
@testable import Store
@testable import Apply
@testable import Sensors

final class PolicyEngineTests: XCTestCase {
    func testEmptyContractEmitsFindingsAndZeroApplies() throws {
        let bundle = try loadFixtureBundle()
        let engine = PolicyEngine()
        let result = engine.evaluate(
            bundle: bundle,
            contract: .emptyDefault(),
            settings: AppSettings(autopilotMasterEnabled: true)
        )
        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertEqual(result.decisions.count, 0)
        XCTAssertEqual(result.autopilotStatus, .off)

        let docked = result.findings.first { $0.id == "energy.dockedSleep" }
        XCTAssertEqual(docked?.severity, .act)
        XCTAssertEqual(docked?.actionIDs, ["energy.ac.sleep.set"])

        let storage = result.findings.first { $0.id == "storage.room" }
        XCTAssertNotNil(storage)
        XCTAssertTrue((storage?.severity ?? .steady) >= .attention)

        let brew = result.findings.first { $0.id == "software.brew.arch" }
        XCTAssertEqual(brew?.severity, .act)
    }

    func testDockedGrantEmitsAutopilotDecisionAfterTwoTicks() throws {
        let bundle = try loadFixtureBundle()
        var contract = Contract.emptyDefault()
        contract.setEnabled("energy.ac.sleep.set", enabled: true)
        var bounds = ActionBounds(min: 15, max: 60, target: 30, powerSource: "AC")
        contract.setBounds("energy.ac.sleep.set", bounds: bounds)

        let engine = PolicyEngine()
        let settings = AppSettings(autopilotMasterEnabled: true)

        let first = engine.evaluate(bundle: bundle, contract: contract, settings: settings)
        XCTAssertEqual(first.decisions.count, 1, "Pulse fight: first confirmed tick should fire")
        XCTAssertEqual(first.decisions[0].actionID, "energy.ac.sleep.set")
        XCTAssertEqual(first.decisions[0].beforeValue, "1")
        XCTAssertEqual(first.decisions[0].afterValue, "30")
        XCTAssertEqual(first.autopilotStatus, .on)

        // Cooldown should suppress an immediate second apply.
        let second = engine.evaluate(bundle: bundle, contract: contract, settings: settings)
        XCTAssertEqual(second.decisions.count, 0, "Cooldown should block immediate re-apply")
    }

    func testJournalWriteAheadWithFakeApplier() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteStore(directory: dir)
        let fake = FakeApplier()
        let journal = JournalCoordinator(store: store, applier: fake)
        let decision = PolicyDecision(
            actionID: "energy.ac.sleep.set",
            beforeValue: "1",
            afterValue: "30",
            parameters: ["key": "sleep", "powerSource": "AC", "value": "30"],
            reason: "test"
        )
        let entry = try journal.apply(decision: decision, actor: .autopilot, killSwitch: false)
        XCTAssertEqual(entry.result, .applied)
        XCTAssertEqual(fake.applied.count, 1)

        let undone = try journal.undo(entryID: entry.id, killSwitch: false)
        XCTAssertEqual(undone.result, .undone)
        XCTAssertEqual(fake.rolledBack.count, 1)
    }

    func testKillSwitchBlocksApply() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try SQLiteStore(directory: dir)
        let fake = FakeApplier()
        let journal = JournalCoordinator(store: store, applier: fake)
        let decision = PolicyDecision(
            actionID: "energy.ac.sleep.set",
            beforeValue: "1",
            afterValue: "30",
            parameters: ["key": "sleep", "powerSource": "AC", "value": "30"],
            reason: "test"
        )
        XCTAssertThrowsError(try journal.apply(decision: decision, actor: .you, killSwitch: true))
        XCTAssertEqual(fake.applied.count, 0)
    }

    private func loadFixtureBundle() throws -> SampleBundle {
        let thisFile = URL(fileURLWithPath: #filePath)
        let url = thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/this-mac.json")
        let data = try Data(contentsOf: url)
        let dict = try FixtureLoader.loadThisMacJSON(data)
        return FixtureLoader.sampleBundle(fromFixture: dict)
    }
}
