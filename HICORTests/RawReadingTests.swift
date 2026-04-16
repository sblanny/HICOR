import XCTest
@testable import HICOR

final class RawReadingTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let original = RawReading(
            id: UUID(),
            sph: 1.50,
            cyl: -0.50,
            ax: 108,
            eye: .right,
            sourcePhotoIndex: 0
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RawReading.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sph, 1.50)
        XCTAssertEqual(decoded.cyl, -0.50)
        XCTAssertEqual(decoded.ax, 108)
        XCTAssertEqual(decoded.eye, .right)
        XCTAssertEqual(decoded.sourcePhotoIndex, 0)
    }

    func testIdentifiableConformance() {
        let r = RawReading(id: UUID(), sph: 0, cyl: 0, ax: 0, eye: .left, sourcePhotoIndex: 0)
        XCTAssertNotNil(r.id)
    }
}
