import XCTest
@testable import HICOR

final class ConstantsTests: XCTestCase {
    func testEyeCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode([Eye.right, Eye.left])
        let decoded = try JSONDecoder().decode([Eye].self, from: encoded)
        XCTAssertEqual(decoded, [.right, .left])
    }

    func testMachineTypeCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode([MachineType.desktop, MachineType.handheld])
        let decoded = try JSONDecoder().decode([MachineType].self, from: encoded)
        XCTAssertEqual(decoded, [.desktop, .handheld])
    }

    func testConsistencyResultCases() {
        let all: [ConsistencyResult] = [.ok, .warningOverridable, .hardBlock]
        XCTAssertEqual(all.count, 3)
    }

    func testPhotoBoundsConstants() {
        // v1 scope reduction: exactly one photo per capture.
        XCTAssertEqual(Constants.minPhotosRequired, 1)
        XCTAssertEqual(Constants.maxPhotosAllowed, 1)
        XCTAssertEqual(Constants.cloudKitContainerID, "iCloud.com.creativearchives.hicor")
    }
}
