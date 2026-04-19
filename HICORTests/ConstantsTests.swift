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

    func testPhotoBoundsConstants() {
        // Clinical requirement per MIKE_RX_PROCEDURE.md: 2–5 printouts per patient.
        XCTAssertEqual(Constants.minPhotosRequired, 2)
        XCTAssertEqual(Constants.maxPhotosAllowed, 5)
        XCTAssertEqual(Constants.cloudKitContainerID, "iCloud.com.creativearchives.hicor")
    }
}
