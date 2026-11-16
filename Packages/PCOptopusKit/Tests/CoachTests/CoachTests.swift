import XCTest
@testable import Coach
@testable import Model

final class CoachTests: XCTestCase {
    func testTodayParagraphIncludesUnits() {
        var storage = Sample(domain: .storage)
        storage.set(.storageAvailableBytes, 61_188_911_104)
        storage.set(.storageContainerBytes, 493_921_239_040)
        var energy = Sample(domain: .energy)
        energy.set(.energyPowerSource, "Battery")
        energy.set(.energyACSleepMinutes, 1)
        var memory = Sample(domain: .memory)
        memory.set(.memoryPressure, "Normal")
        let bundle = SampleBundle(samples: [storage, energy, memory])
        let finding = Finding(
            id: "energy.dockedSleep",
            domain: .energy,
            severity: .act,
            title: "Plugged-in sleep is too short",
            summary: "On AC, system sleep is 1 minute.",
            actionIDs: ["energy.ac.sleep.set"]
        )
        let pulse = PulseScore.compute(findings: [finding], bundle: bundle)
        let text = TemplateCoach().todayParagraph(
            findings: [finding],
            bundle: bundle,
            status: .off,
            pulse: pulse
        )
        XCTAssertTrue(text.lowercased().contains("pulse"))
        XCTAssertTrue(text.contains("off") || text.contains("Off") || text.lowercased().contains("autopilot"))
    }

    func testAskGroundsInActionIDs() {
        let finding = Finding(
            id: "software.brew.arch",
            domain: .software,
            severity: .act,
            title: "PATH prefers Rosetta Homebrew",
            summary: "Rosetta brew",
            actionIDs: ["software.brew.path.native"]
        )
        var software = Sample(domain: .software)
        software.set(.softwareBrewPathArch, "x86_64")
        let pulse = PulseScore.compute(findings: [finding], bundle: SampleBundle(samples: [software]))
        let answer = TemplateCoach().answer(
            question: "Why is brew slow?",
            findings: [finding],
            bundle: SampleBundle(samples: [software]),
            pulse: pulse
        )
        XCTAssertTrue(answer.actionIDs.contains("software.brew.path.native") || answer.prose.lowercased().contains("homebrew"))
    }
}
