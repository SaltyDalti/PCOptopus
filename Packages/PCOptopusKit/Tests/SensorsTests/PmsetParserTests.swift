import XCTest
@testable import Sensors

final class PmsetParserTests: XCTestCase {
    func testParseCustomACSleepOneVersusBatteryFifteen() {
        let fixture = """
        AC Power:
         Sleep On Power Button 1
         standby              0
         hibernatemode        0
         powernap             1
         hibernatefile        /var/vm/sleepimage
         ttyskeepawake        1
         womp                 1
         displaysleep         10
         networkoversleep     0
         sleep                1
         tcpkeepalive         1
         disksleep            10
        Battery Power:
         Sleep On Power Button 1
         standby              1
         hibernatemode        3
         powernap             0
         hibernatefile        /var/vm/sleepimage
         ttyskeepawake        1
         womp                 0
         displaysleep         30
         networkoversleep     0
         sleep                15
         tcpkeepalive         1
         disksleep            0
        """
        let parsed = PmsetParser.parseCustom(fixture)
        XCTAssertEqual(parsed.ac.sleep, 1)
        XCTAssertEqual(parsed.ac.displaysleep, 10)
        XCTAssertEqual(parsed.ac.disksleep, 10)
        XCTAssertEqual(parsed.ac.powernap, 1)
        XCTAssertEqual(parsed.battery.sleep, 15)
        XCTAssertEqual(parsed.battery.displaysleep, 30)
        XCTAssertEqual(parsed.battery.hibernatemode, 3)
    }

    func testFixtureBundleLoadsLeadMetrics() throws {
        let url = fixtureURL()
        let data = try Data(contentsOf: url)
        let dict = try FixtureLoader.loadThisMacJSON(data)
        let bundle = FixtureLoader.sampleBundle(fromFixture: dict)
        XCTAssertEqual(bundle.int(.energyACSleepMinutes), 1)
        XCTAssertEqual(bundle.int(.energyBatterySleepMinutes), 15)
        XCTAssertEqual(bundle.string(.softwareBrewPathArch), "x86_64")
        let available = try XCTUnwrap(bundle.double(.storageAvailableBytes))
        XCTAssertLessThan(available, 80_000_000_000)
    }

    private func fixtureURL() -> URL {
        // Prefer bundled resource, then repo-relative Fixtures.
        if let bundled = Bundle.module.url(forResource: "this-mac", withExtension: "json", subdirectory: "Fixtures") {
            return bundled
        }
        if let bundled = Bundle.module.url(forResource: "this-mac", withExtension: "json") {
            return bundled
        }
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent() // SensorsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PCOptopusKit
            .deletingLastPathComponent() // Packages
            .appendingPathComponent("Fixtures/this-mac.json")
    }
}
