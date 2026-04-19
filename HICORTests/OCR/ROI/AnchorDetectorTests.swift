import XCTest
import UIKit
@testable import HICOR

/// Canned LineRecognizing stub for tests.
private struct StubLineRecognizer: LineRecognizing {
    let lines: [OCRLine]
    func recognize(_ image: UIImage) async throws -> [OCRLine] { lines }
}

final class AnchorDetectorTests: XCTestCase {

    private func blankImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1100)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1100))
        }
    }

    // Layout matches CellLayoutTests.syntheticAnchors(): right section in
    // top half (Y 0-600), left section in bottom half (Y 600-1100).
    private func fullLineSet() -> [OCRLine] {
        [
            OCRLine(text: "<R>", frame: CGRect(x: 1340, y:  60, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  120, y: 100, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  120, y: 240, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x:  120, y: 380, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  120, y: 520, width: 80, height: 60)),

            OCRLine(text: "<L>", frame: CGRect(x: 1340, y: 640, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  120, y: 680, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  120, y: 800, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x:  120, y: 920, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  120, y:1040, width: 80, height: 60))
        ]
    }

    func testDetectAllAnchorsProducesRightAndLeftSections() async throws {
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: fullLineSet()))
        let anchors = try await detector.detectAnchors(in: blankImage())
        XCTAssertEqual(anchors.right.sph.origin.y, 100)
        XCTAssertEqual(anchors.left.sph.origin.y,  680)
    }

    func testAcceptsBracketStyleVariants() async throws {
        var lines = fullLineSet()
        // Swap <R>/<L> for [R]/[L] to test case-insensitive match on both.
        lines[0] = OCRLine(text: "[R]", frame: lines[0].frame)
        lines[5] = OCRLine(text: "[L]", frame: lines[5].frame)
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        _ = try await detector.detectAnchors(in: blankImage())
    }

    func testThrowsInsufficientAnchorsWhenRightSectionMissingMultiple() async {
        var lines = fullLineSet()
        lines.removeAll { $0.text == "SPH" && $0.frame.origin.y < 600 }
        lines.removeAll { $0.text == "CYL" && $0.frame.origin.y < 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        do {
            _ = try await detector.detectAnchors(in: blankImage())
            XCTFail("expected throw")
        } catch AnchorDetector.Error.insufficientAnchors(let missing) {
            XCTAssertTrue(missing.contains(where: { $0.contains("SPH") }))
            XCTAssertTrue(missing.contains(where: { $0.contains("CYL") }))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInterpolatesSingleMissingAnchor() async throws {
        var lines = fullLineSet()
        // Drop the right-section CYL anchor. Single missing → interpolate
        // from SPH and AX.
        lines.removeAll { $0.text == "CYL" && $0.frame.origin.y < 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        let anchors = try await detector.detectAnchors(in: blankImage())
        // SPH at y=100, AX at y=380. Midpoint → y≈240.
        XCTAssertEqual(anchors.right.cyl.midY, 270, accuracy: 30)
    }
}
