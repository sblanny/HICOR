import XCTest
@testable import HICOR

final class EyeReadingTests: XCTestCase {
    func testCodableRoundTripWithMachineAvg() throws {
        let r1 = RawReading(id: UUID(), sph: 1.50, cyl: -0.25, ax: 108, eye: .right, sourcePhotoIndex: 0)
        let r2 = RawReading(id: UUID(), sph: 1.25, cyl: -1.00, ax: 114, eye: .right, sourcePhotoIndex: 0)
        let original = EyeReading(
            id: UUID(),
            eye: .right,
            readings: [r1, r2],
            machineAvgSPH: 1.50,
            machineAvgCYL: -0.50,
            machineAvgAX: 108,
            sourcePhotoIndex: 0,
            machineType: .desktop
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EyeReading.self, from: data)
        XCTAssertEqual(decoded.eye, .right)
        XCTAssertEqual(decoded.readings.count, 2)
        XCTAssertEqual(decoded.machineAvgSPH, 1.50)
        XCTAssertEqual(decoded.machineAvgCYL, -0.50)
        XCTAssertEqual(decoded.machineAvgAX, 108)
        XCTAssertEqual(decoded.machineType, .desktop)
    }

    func testCodableRoundTripWithoutMachineAvg() throws {
        let original = EyeReading(
            id: UUID(),
            eye: .left,
            readings: [],
            machineAvgSPH: nil,
            machineAvgCYL: nil,
            machineAvgAX: nil,
            sourcePhotoIndex: 1,
            machineType: .handheld
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EyeReading.self, from: data)
        XCTAssertNil(decoded.machineAvgSPH)
        XCTAssertNil(decoded.machineAvgCYL)
        XCTAssertNil(decoded.machineAvgAX)
        XCTAssertEqual(decoded.machineType, .handheld)
    }
}
