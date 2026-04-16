import XCTest
@testable import HICOR

final class ConsistencyValidatorTests: XCTestCase {

    private func makeResult(
        rightSPHs: [Double],
        leftSPHs: [Double],
        rightCYLs: [Double]? = nil,
        leftCYLs: [Double]? = nil,
        photoIndex: Int = 0
    ) -> PrintoutResult {
        let rCyls = rightCYLs ?? Array(repeating: -0.50, count: rightSPHs.count)
        let lCyls = leftCYLs  ?? Array(repeating: -0.50, count: leftSPHs.count)
        let rRight = zip(rightSPHs, rCyls).map { (sph, cyl) in
            RawReading(id: UUID(), sph: sph, cyl: cyl, ax: 90, eye: .right, sourcePhotoIndex: photoIndex)
        }
        let rLeft = zip(leftSPHs, lCyls).map { (sph, cyl) in
            RawReading(id: UUID(), sph: sph, cyl: cyl, ax: 90, eye: .left, sourcePhotoIndex: photoIndex)
        }
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: photoIndex, machineType: .desktop)
        let left  = EyeReading(id: UUID(), eye: .left,  readings: rLeft,  machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: photoIndex, machineType: .desktop)
        return PrintoutResult(rightEye: right, leftEye: left, pd: nil, machineType: .desktop, sourcePhotoIndex: photoIndex, rawText: "")
    }

    func testSignMismatchWithTwoPhotosTriggersHardBlock() {
        let r = makeResult(rightSPHs: [+1.50], leftSPHs: [-2.00])
        let outcome = ConsistencyValidator().validate([r], photoCount: 2)
        XCTAssertEqual(outcome.result, .hardBlock)
        XCTAssertNotNil(outcome.message)
    }

    func testSignMismatchWithThreePhotosIsOverridable() {
        let r = makeResult(rightSPHs: [+1.50], leftSPHs: [-2.00])
        let outcome = ConsistencyValidator().validate([r], photoCount: 3)
        XCTAssertEqual(outcome.result, .warningOverridable)
    }

    func testTightSpreadWithinThresholdIsOK() {
        let r = makeResult(rightSPHs: [-2.00, -2.25, -2.00], leftSPHs: [-2.00, -2.25, -2.25])
        let outcome = ConsistencyValidator().validate([r], photoCount: 3)
        XCTAssertEqual(outcome.result, .ok)
    }

    func testSPHSpreadAboveThresholdIsOverridable() {
        // Spread of 1.00 D > 0.75 D threshold
        let r = makeResult(rightSPHs: [-2.00, -3.00, -2.50], leftSPHs: [-2.00, -2.25])
        let outcome = ConsistencyValidator().validate([r], photoCount: 3)
        XCTAssertEqual(outcome.result, .warningOverridable)
        XCTAssertNotNil(outcome.message)
    }
}
