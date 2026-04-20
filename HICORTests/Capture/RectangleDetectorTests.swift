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

    func testResultsAreSortedByConfidenceDescending() throws {
        let image = try firstFixture(prefix: "dim_good_framing-case-")
        let results = detector.detectSync(in: image.cgImage!)
        guard results.count > 1 else {
            throw XCTSkip("Fixture only produced one rectangle; sort order trivially satisfied")
        }
        for i in 1..<results.count {
            XCTAssertGreaterThanOrEqual(results[i - 1].confidence, results[i].confidence)
        }
    }

    func testAllFixturesDetectAboveThresholds() throws {
        // Calibration evidence (2026-04-20, all 6 dim_good_framing fixtures):
        // confidence=1.000 on every fixture; aspect range 0.579–0.992;
        // min-dimension (derived from boundingBox + aspect) ≥0.307.
        // Every fixture clears thresholds with margin ≥0.1; maximumAspectRatio=1.0
        // is the framework ceiling (aspect is always ≤1.0 by definition), tightest
        // observed value is 0.992 on fixture 1776551538.
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
