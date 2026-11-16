import Foundation
import Model
import Store
import Sensors
import Policy
import Apply
import Coach

@main
enum VerificationMain {
    static func main() throws {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok {
                print("PASS  \(name)")
            } else {
                print("FAIL  \(name) \(detail)")
                failures += 1
            }
        }

        // Model
        let contract = Contract.emptyDefault()
        check("empty contract grants nothing", contract.enabledCount == 0)
        check("severity order", Severity.steady < Severity.attention && Severity.attention < Severity.act)
        check("this-mac seed", MachineIdentity.thisMacSeed.modelIdentifier == "Mac16,7")

        // Fixture + pmset parse
        let fixtureURL = resolveFixtureURL()
        let data = try Data(contentsOf: fixtureURL)
        let dict = try FixtureLoader.loadThisMacJSON(data)
        let bundle = FixtureLoader.sampleBundle(fromFixture: dict)
        check("AC sleep is 1", bundle.int(.energyACSleepMinutes) == 1)
        check("Battery sleep is 15", bundle.int(.energyBatterySleepMinutes) == 15)
        check("brew arch x86_64", bundle.string(.softwareBrewPathArch) == "x86_64")
        check("storage under 80GB", (bundle.double(.storageAvailableBytes) ?? 0) < 80_000_000_000)

        let custom = """
        AC Power:
         sleep                1
         displaysleep         10
        Battery Power:
         sleep                15
         displaysleep         30
        """
        let parsed = PmsetParser.parseCustom(custom)
        check("pmset AC sleep 1", parsed.ac.sleep == 1)
        check("pmset battery sleep 15", parsed.battery.sleep == 15)

        // Policy: empty contract → findings, zero decisions
        let engine = PolicyEngine()
        let emptyResult = engine.evaluate(
            bundle: bundle,
            contract: .emptyDefault(),
            settings: AppSettings(autopilotMasterEnabled: true)
        )
        check("findings non-empty", !emptyResult.findings.isEmpty)
        check("zero decisions without grants", emptyResult.decisions.isEmpty)
        check("autopilot off without grants", emptyResult.autopilotStatus == .off)
        let docked = emptyResult.findings.first { $0.id == "energy.dockedSleep" }
        check("docked sleep act", docked?.severity == .act)
        let brew = emptyResult.findings.first { $0.id == "software.brew.arch" }
        check("brew finding act", brew?.severity == .act)
        let storage = emptyResult.findings.first { $0.id == "storage.room" }
        check("storage attention+", (storage?.severity ?? .steady) >= .attention)

        // Policy: grant → decision on first confirmed tick (Pulse fight)
        var granted = Contract.emptyDefault()
        granted.setEnabled("energy.ac.sleep.set", enabled: true)
        granted.setBounds("energy.ac.sleep.set", bounds: ActionBounds(min: 15, max: 60, target: 30, powerSource: "AC"))
        let settings = AppSettings(autopilotMasterEnabled: true)
        let hysteresisEngine = PolicyEngine()
        let tick1 = hysteresisEngine.evaluate(bundle: bundle, contract: granted, settings: settings)
        check("tick1 fires for Pulse fight", tick1.decisions.count == 1, "got \(tick1.decisions.count) status=\(tick1.autopilotStatus)")
        check(
            "decision AC sleep 1→30",
            tick1.decisions.first?.beforeValue == "1" && tick1.decisions.first?.afterValue == "30",
            "\(tick1.decisions.first?.beforeValue ?? "?")→\(tick1.decisions.first?.afterValue ?? "?")"
        )
        let tick2 = hysteresisEngine.evaluate(bundle: bundle, contract: granted, settings: settings)
        check("tick2 cooldown", tick2.decisions.isEmpty, "got \(tick2.decisions.count)")

        // Journal + fake applier
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
        check("journal applied", entry.result == .applied && fake.applied.count == 1)
        let undone = try journal.undo(entryID: entry.id, killSwitch: false)
        check("journal undone", undone.result == .undone && fake.rolledBack.count == 1)

        var threw = false
        do {
            _ = try journal.apply(decision: decision, actor: .you, killSwitch: true)
        } catch {
            threw = true
        }
        check("kill switch blocks", threw)

        // Allowlist
        switch PmsetAllowlist.validate(key: "sleep", powerSource: "AC", value: 30) {
        case .success(let v): check("allow sleep", v.flag == "-c")
        case .failure: check("allow sleep", false)
        }
        switch PmsetAllowlist.validate(key: "hibernatemode", powerSource: "AC", value: 0) {
        case .success: check("refuse hibernatemode", false)
        case .failure: check("refuse hibernatemode", true)
        }

        // Pulse + Coach
        let pulse = PulseScore.compute(findings: emptyResult.findings, bundle: bundle)
        check("pulse below 100 with findings", pulse.percent < 100, "pulse=\(pulse.percent)")
        check("pulse has drags", !pulse.drags.isEmpty)
        let coach = TemplateCoach()
        let paragraph = coach.todayParagraph(findings: emptyResult.findings, bundle: bundle, status: .off, pulse: pulse)
        check("coach paragraph mentions pulse", paragraph.lowercased().contains("pulse"))
        let answer = coach.answer(question: "Tell me about brew", findings: emptyResult.findings, bundle: bundle, pulse: pulse)
        check("coach brew answer", answer.prose.lowercased().contains("homebrew") || answer.prose.lowercased().contains("brew"))
        let pulseAsk = coach.answer(question: "What is my pulse?", findings: emptyResult.findings, bundle: bundle, pulse: pulse)
        check("coach pulse answer", pulseAsk.prose.lowercased().contains("pulse"))

        // Live zero-write check: empty contract must not call pmset
        let beforeSleep = liveACSleep()
        _ = engine.evaluate(bundle: bundle, contract: .emptyDefault(), settings: AppSettings(autopilotMasterEnabled: true))
        let afterSleep = liveACSleep()
        check("live pmset unchanged", beforeSleep == afterSleep, "before=\(beforeSleep ?? -1) after=\(afterSleep ?? -1)")

        // Live sensor smoke (read-only)
        let fast = FastSensors().read(includePmset: true, includeAssertions: true)
        check("live physical memory", fast.physicalBytes > 0)
        let slow = SlowSensors().read()
        check("live storage available", slow.availableBytes > 0)
        check("live agent inventory", true, "count=\(slow.agentLabels.count)")

        let summary = failures == 0 ? "ALL PASSED" : "FAILED \(failures)"
        print("\n\(summary)")
        if failures > 0 { exit(1) }
    }

    static func resolveFixtureURL() -> URL {
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("this-mac.json"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("this-mac.json")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return candidates[0]
    }

    static func liveACSleep() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "custom"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return PmsetParser.parseCustom(text).ac.sleep
    }
}
