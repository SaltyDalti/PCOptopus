import XCTest
@testable import Apply

final class PmsetAllowlistTests: XCTestCase {
    func testAllowsSleepOnAC() {
        switch PmsetAllowlist.validate(key: "sleep", powerSource: "AC", value: 30) {
        case .success(let v):
            XCTAssertEqual(v.flag, "-c")
            XCTAssertEqual(v.key, "sleep")
            XCTAssertEqual(v.value, 30)
        case .failure(let error):
            XCTFail("\(error)")
        }
    }

    func testRefusesUnknownKey() {
        switch PmsetAllowlist.validate(key: "hibernatemode", powerSource: "AC", value: 0) {
        case .success:
            XCTFail("hibernatemode must be refused")
        case .failure(let error):
            guard case .refusedKey = error else {
                XCTFail("expected refusedKey")
                return
            }
        }
    }

    func testFakeApplierRecords() throws {
        let fake = FakeApplier()
        _ = try fake.apply(
            actionID: "energy.ac.sleep.set",
            parameters: ["key": "sleep", "value": "30"],
            killSwitch: false
        )
        XCTAssertEqual(fake.applied.count, 1)
        XCTAssertThrowsError(try fake.apply(actionID: "x", parameters: [:], killSwitch: true))
    }
}
