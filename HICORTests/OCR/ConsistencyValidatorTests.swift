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

    func testSignMismatchOnSinglePhotoIsOverridable() {
        // v1 scope reduction: with one photo there is no "ask for more printouts"
        // path, so any sign mismatch is warningOverridable, never hardBlock.
        let r = makeResult(rightSPHs: [+1.50], leftSPHs: [-2.00])
        let outcome = ConsistencyValidator().validate([r])
        XCTAssertEqual(outcome.result, .warningOverridable)
        XCTAssertNotNil(outcome.message)
    }

    func testTightSpreadWithinThresholdIsOK() {
        let r = makeResult(rightSPHs: [-2.00, -2.25, -2.00], leftSPHs: [-2.00, -2.25, -2.25])
        let outcome = ConsistencyValidator().validate([r])
        XCTAssertEqual(outcome.result, .ok)
    }

    func testSPHSpreadAboveThresholdIsOverridable() {
        // Spread of 1.00 D > 0.75 D threshold
        let r = makeResult(rightSPHs: [-2.00, -3.00, -2.50], leftSPHs: [-2.00, -2.25])
        let outcome = ConsistencyValidator().validate([r])
        XCTAssertEqual(outcome.result, .warningOverridable)
        XCTAssertNotNil(outcome.message)
    }

    func testImplausibleSphValuesFilteredFromSignAverage() {
        // Defense-in-depth: even if a parser regression injects sph=+90 (an axis
        // misread as SPH), the validator must drop it instead of letting it flip
        // the eye's average sign and trigger a false mismatch.
        let rRight = [
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: -2.25, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0)
        ]
        let rLeft = [
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0),
            RawReading(id: UUID(), sph: +90.0, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0)  // implausible: would flip avg
        ]
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let left  = EyeReading(id: UUID(), eye: .left,  readings: rLeft,  machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let result = PrintoutResult(rightEye: right, leftEye: left, pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "")
        let outcome = ConsistencyValidator().validate([result])
        XCTAssertEqual(outcome.result, .ok, "Implausible SPH must be filtered out, leaving both eyes negative → ok")
    }

    func testSphOnlyReadingsExcludedFromCylSpreadCheck() {
        // CYL placeholders on isSphOnly readings (0.0) would falsely show a 1.00 D spread
        // against a real -1.00 cyl reading. Validator must filter them out.
        let rRight = [
            RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0, isSphOnly: false),
            RawReading(id: UUID(), sph: -2.00, cyl: 0.0,   ax: 0,  eye: .right, sourcePhotoIndex: 0, isSphOnly: true),
            RawReading(id: UUID(), sph: -2.00, cyl: -1.00, ax: 90, eye: .right, sourcePhotoIndex: 0, isSphOnly: false)
        ]
        let rLeft = [
            RawReading(id: UUID(), sph: -2.00, cyl: -0.50, ax: 90, eye: .left, sourcePhotoIndex: 0)
        ]
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let left  = EyeReading(id: UUID(), eye: .left,  readings: rLeft,  machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let result = PrintoutResult(rightEye: right, leftEye: left, pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "")
        let outcome = ConsistencyValidator().validate([result])
        XCTAssertEqual(outcome.result, .ok, "isSphOnly placeholders must not trigger cyl spread warning")
    }

    func testSignMismatchSkippedWhenOneEyeBlind() {
        // Right eye populated with + SPH, left eye blind (nil EyeReading).
        // Without a left eye, there is no sign to mismatch against — should be .ok.
        let rRight = [RawReading(id: UUID(), sph: +1.50, cyl: -0.50, ax: 90, eye: .right, sourcePhotoIndex: 0)]
        let right = EyeReading(id: UUID(), eye: .right, readings: rRight, machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil, sourcePhotoIndex: 0, machineType: .handheld)
        let result = PrintoutResult(rightEye: right, leftEye: nil, pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "")
        let outcome = ConsistencyValidator().validate([result])
        XCTAssertEqual(outcome.result, .ok, "Blind-eye cases must not trigger sign mismatch")
    }
}
