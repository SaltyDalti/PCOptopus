import XCTest
@testable import Model

final class ModelTests: XCTestCase {
    func testContractEmptyMeansNothingGranted() {
        let contract = Contract.emptyDefault()
        XCTAssertEqual(contract.enabledCount, 0)
        XCTAssertFalse(contract.isGranted("energy.ac.sleep.set"))
    }

    func testSeverityOrdering() {
        XCTAssertTrue(Severity.steady < Severity.attention)
        XCTAssertTrue(Severity.attention < Severity.act)
    }

    func testFormattersAvailableOfTotal() {
        let text = Formatters.availableOfTotal(available: 61_188_911_104, total: 493_921_239_040)
        XCTAssertTrue(text.contains("available of"))
        XCTAssertTrue(text.contains("GB"))
    }

    func testSampleMetricAccessors() {
        var sample = Sample(domain: .energy)
        sample.set(.energyACSleepMinutes, 1)
        sample.set(.energyPowerSource, PowerSourceValue.ac.rawValue)
        XCTAssertEqual(sample.int(.energyACSleepMinutes), 1)
        XCTAssertEqual(sample.string(.energyPowerSource), "AC")
    }

    func testThisMacSeedIdentity() {
        let m = MachineIdentity.thisMacSeed
        XCTAssertEqual(m.modelIdentifier, "Mac16,7")
        XCTAssertEqual(m.performanceCores, 10)
        XCTAssertEqual(m.efficiencyCores, 4)
        XCTAssertTrue(m.sipEnabled)
    }
}
