import XCTest
@testable import HICOR

final class StabilityDetectorTests: XCTestCase {
    func testEmptyHistoryIsNotStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        XCTAssertFalse(detector.isStable)
    }

    func testIdenticalDetectionsAreStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        let rect = makeRect(offset: .zero)
        for _ in 0..<15 { detector.append(rect) }
        XCTAssertTrue(detector.isStable)
    }

    func testJitterWithinToleranceIsStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        for i in 0..<15 {
            detector.append(makeRect(offset: CGPoint(x: CGFloat(i % 3) - 1, y: CGFloat(i % 3) - 1)))
        }
        XCTAssertTrue(detector.isStable)
    }

    func testOutlierBeyondToleranceIsNotStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        for _ in 0..<14 { detector.append(makeRect(offset: .zero)) }
        detector.append(makeRect(offset: CGPoint(x: 50, y: 50)))
        XCTAssertFalse(detector.isStable)
    }

    func testOutlierCyclesOutAndBecomesStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        detector.append(makeRect(offset: CGPoint(x: 50, y: 50)))
        for _ in 0..<15 { detector.append(makeRect(offset: .zero)) }
        XCTAssertTrue(detector.isStable)
    }

    func testNilAppendClearsHistory() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        for _ in 0..<15 { detector.append(makeRect(offset: .zero)) }
        XCTAssertTrue(detector.isStable)
        detector.append(nil)
        XCTAssertFalse(detector.isStable)
        XCTAssertNil(detector.current)
    }

    func testDriftBeyondToleranceIsNotStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        for i in 0..<15 {
            detector.append(makeRect(offset: CGPoint(x: CGFloat(i) * 2, y: 0)))
        }
        XCTAssertFalse(detector.isStable)
    }

    func testPartialWindowIsNotStable() {
        let detector = StabilityDetector(windowSize: 15, tolerance: 10)
        for _ in 0..<10 { detector.append(makeRect(offset: .zero)) }
        XCTAssertFalse(detector.isStable)
    }

    // MARK: - Helpers

    private func makeRect(offset: CGPoint) -> DetectedRectangle {
        DetectedRectangle(
            topLeft:     CGPoint(x: 100 + offset.x, y: 100 + offset.y),
            topRight:    CGPoint(x: 500 + offset.x, y: 100 + offset.y),
            bottomRight: CGPoint(x: 500 + offset.x, y: 900 + offset.y),
            bottomLeft:  CGPoint(x: 100 + offset.x, y: 900 + offset.y),
            confidence: 0.9,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.8)
        )
    }
}
