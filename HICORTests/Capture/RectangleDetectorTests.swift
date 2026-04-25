import XCTest
import UIKit
@testable import HICOR

final class RectangleDetectorTests: XCTestCase {
    private var detector: RectangleDetector!
    private let bundle = Bundle(for: RectangleDetectorTests.self)

    override func setUp() {
        super.setUp()
        detector = RectangleDetector()
    }

    func testDetectsRectangleInRealPrintoutFixture() throws {
        let image = try firstFixture(prefix: "dim_good_framing-case-")
        let results = detector.detectSync(in: image.cgImage!)
        XCTAssertFalse(results.isEmpty, "Expected at least one rectangle in a real printout photo")
        XCTAssertGreaterThanOrEqual(results.first!.confidence, RectangleDetector.minimumConfidence)
    }

    func testReturnsEmptyOnFlatGrayImage() {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
        }
        let results = detector.detectSync(in: blank.cgImage!)
        XCTAssertTrue(results.isEmpty)
    }

    func testResultsAreSortedByAreaDescending() throws {
        let image = try firstFixture(prefix: "dim_good_framing-case-")
        let results = detector.detectSync(in: image.cgImage!)
        guard results.count > 1 else {
            throw XCTSkip("Fixture only produced one rectangle; sort order trivially satisfied")
        }
        for i in 1..<results.count {
            let prev = results[i - 1].boundingBox
            let curr = results[i].boundingBox
            let prevArea = prev.width * prev.height
            let currArea = curr.width * curr.height
            // Within the 2% similar-area tolerance confidence breaks the tie either way,
            // so only assert strict area ordering when the gap exceeds the tolerance.
            if abs(prevArea - currArea) >= CGFloat(RectangleDetector.similarAreaTolerance) {
                XCTAssertGreaterThanOrEqual(prevArea, currArea,
                    "results should be sorted by area descending")
            }
        }
    }

    func testSortPrefersLargerAreaOverHigherConfidence() {
        // Interior sections of a printout (R-eye block, AVG-bounded box) often score
        // higher confidence than the outer paper because their edges are crisp white-on-white,
        // while the paper's edge against a wood surface is softer. Area-first sort ensures the
        // outer paper — always the larger rectangle — wins.
        let smallHighConf = DetectedRectangle(
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.95,
            boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)   // area 0.16
        )
        let largeLowConf = DetectedRectangle(
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.70,
            boundingBox: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9) // area 0.81
        )
        let sorted = RectangleDetector.sortedByPreference([smallHighConf, largeLowConf])
        XCTAssertEqual(sorted.first?.confidence, 0.70,
                       "larger rectangle should rank first even with lower confidence")
    }

    func testSortUsesConfidenceAsTiebreakerForSimilarAreas() {
        let lowConf = DetectedRectangle(
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.70,
            boundingBox: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)       // area 0.25
        )
        let highConf = DetectedRectangle(
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.95,
            boundingBox: CGRect(x: 0, y: 0, width: 0.505, height: 0.505)   // area ≈0.255, within 0.02
        )
        let sorted = RectangleDetector.sortedByPreference([lowConf, highConf])
        XCTAssertEqual(sorted.first?.confidence, 0.95)
    }

    func testRealPrintoutDetectsFullOutlineNotInteriorSection() throws {
        let image = try firstFixture(prefix: "dim_good_framing-case-")
        let results = detector.detectSync(in: image.cgImage!)
        guard let top = results.first else {
            XCTFail("expected at least one rectangle"); return
        }
        XCTAssertGreaterThan(top.boundingBox.width, 0.5,
            "top rectangle should span the outer paper, not a narrow interior section")
    }

    func testAllFixturesDetectAboveThresholds() throws {
        // Detector uses VNDetectDocumentSegmentationRequest (neural-net document segmenter),
        // which expresses no aspect/size knobs — only confidence is filterable. Every
        // dim_good_framing fixture should return a segmented document whose confidence
        // clears the minimumConfidence floor.
        let jpgs = bundle.paths(forResourcesOfType: "jpg", inDirectory: nil)
            .filter { URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("dim_good_framing-case-") }
        guard !jpgs.isEmpty else { throw XCTSkip("no fixtures") }
        XCTAssertEqual(jpgs.count, 6, "expected all 6 dim_good_framing fixtures bundled")
        for path in jpgs {
            guard let image = UIImage(contentsOfFile: path), let cg = image.cgImage else {
                XCTFail("could not load \(path)"); continue
            }
            let results = detector.detectSync(in: cg)
            XCTAssertFalse(results.isEmpty, "fixture \(path) produced no rectangles")
            XCTAssertGreaterThanOrEqual(results[0].confidence, RectangleDetector.minimumConfidence)
        }
    }

    // MARK: - Helpers

    private func firstFixture(prefix: String) throws -> UIImage {
        let jpgs = bundle.paths(forResourcesOfType: "jpg", inDirectory: nil)
        guard let path = jpgs.first(where: { URL(fileURLWithPath: $0).lastPathComponent.hasPrefix(prefix) }),
              let image = UIImage(contentsOfFile: path) else {
            throw XCTSkip("no bundled fixture with prefix \(prefix)")
        }
        return image
    }
}
