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

    func testLowConfidenceDefaultsToFalse() {
        let r = RawReading(id: UUID(), sph: 0, cyl: 0, ax: 0, eye: .right, sourcePhotoIndex: 0)
        XCTAssertFalse(r.lowConfidence)
    }

    func testLowConfidenceTrueSurvivesCodableRoundTrip() throws {
        let original = RawReading(
            id: UUID(),
            sph: -3.25,
            cyl: -1.00,
            ax: 81,
            eye: .right,
            sourcePhotoIndex: 2,
            lowConfidence: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RawReading.self, from: data)
        XCTAssertTrue(decoded.lowConfidence)
    }

    func testDecodingLegacyJSONWithoutLowConfidenceDefaultsToFalse() throws {
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "sph": 1.5,
          "cyl": -0.5,
          "ax": 108,
          "eye": "right",
          "sourcePhotoIndex": 0
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RawReading.self, from: legacyJSON)
        XCTAssertFalse(decoded.lowConfidence)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.sph, 1.5)
    }

    func testIsSphOnlyDefaultsToFalse() {
        let r = RawReading(id: UUID(), sph: -2.00, cyl: 0, ax: 0, eye: .right, sourcePhotoIndex: 0)
        XCTAssertFalse(r.isSphOnly)
    }

    func testIsSphOnlyTrueSurvivesCodableRoundTrip() throws {
        let original = RawReading(
            id: UUID(),
            sph: -2.00,
            cyl: 0.0,
            ax: 0,
            eye: .left,
            sourcePhotoIndex: 1,
            isSphOnly: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RawReading.self, from: data)
        XCTAssertTrue(decoded.isSphOnly)
        XCTAssertEqual(decoded.sph, -2.00)
        XCTAssertEqual(decoded.cyl, 0.0)
        XCTAssertEqual(decoded.ax, 0)
    }

    func testDecodingLegacyJSONWithoutIsSphOnlyDefaultsToFalse() throws {
        let id = UUID()
        let legacyJSON = """
        {
          "id": "\(id.uuidString)",
          "sph": -2.0,
          "cyl": -0.5,
          "ax": 90,
          "eye": "right",
          "sourcePhotoIndex": 0,
          "lowConfidence": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RawReading.self, from: legacyJSON)
        XCTAssertFalse(decoded.isSphOnly)
    }
}
