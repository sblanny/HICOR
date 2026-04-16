import XCTest
@testable import HICOR

final class LensInventoryTests: XCTestCase {
    func testLensOptionCodableRoundTrip() throws {
        let opt = LensOption(id: UUID(), sph: 1.50, cyl: -0.50, available: true)
        let data = try JSONEncoder().encode(opt)
        let decoded = try JSONDecoder().decode(LensOption.self, from: data)
        XCTAssertEqual(decoded, opt)
    }

    func testLensOptionEquatable() {
        let id = UUID()
        let a = LensOption(id: id, sph: 1.0, cyl: -0.5, available: true)
        let b = LensOption(id: id, sph: 1.0, cyl: -0.5, available: true)
        XCTAssertEqual(a, b)
    }

    func testLensInventoryCodableRoundTrip() throws {
        let inv = LensInventory(
            version: "1.0",
            lastUpdated: Date(timeIntervalSince1970: 0),
            supportedCylinders: [0.0, -0.50, -1.00, -1.50, -2.00],
            lenses: [
                LensOption(id: UUID(), sph: 0.00, cyl: 0.00, available: true),
                LensOption(id: UUID(), sph: 1.25, cyl: -0.50, available: false)
            ]
        )
        let data = try JSONEncoder().encode(inv)
        let decoded = try JSONDecoder().decode(LensInventory.self, from: data)
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertEqual(decoded.supportedCylinders, [0.0, -0.50, -1.00, -1.50, -2.00])
        XCTAssertEqual(decoded.lenses.count, 2)
    }
}
