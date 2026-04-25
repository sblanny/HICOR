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

    // Layout models the real GRK-6000 printout: column headers are
    // horizontal (different X, same Y per eye) and AVG prints below the
    // three data rows. Right section on top, left on bottom. AVG sits
    // ~220 Y-units below its section's headers to match real captures.
    private func fullLineSet() -> [OCRLine] {
        [
            OCRLine(text: "<R>", frame: CGRect(x:  120, y:  80, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  400, y: 160, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  700, y: 160, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x: 1000, y: 160, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  200, y: 380, width: 80, height: 60)),

            OCRLine(text: "<L>", frame: CGRect(x:  120, y: 680, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  400, y: 760, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  700, y: 760, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x: 1000, y: 760, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  200, y: 980, width: 80, height: 60))
        ]
    }

    func testDetectAllAnchorsProducesRightAndLeftSections() async throws {
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: fullLineSet()))
        let anchors = try await detector.detectAnchors(in: blankImage())
        XCTAssertEqual(anchors.right.sph.origin.y, 160)
        XCTAssertEqual(anchors.left.sph.origin.y,  760)
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
        // from SPH and AX (both at y=160, midY=190 with height 60).
        lines.removeAll { $0.text == "CYL" && $0.frame.origin.y < 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        let anchors = try await detector.detectAnchors(in: blankImage())
        XCTAssertEqual(anchors.right.cyl.midY, 190, accuracy: 5)
        // X should sit between SPH.midX (440) and AX.midX (1040) closer to
        // CYL's natural position (~0.583 from SPH toward AX → ~790).
        XCTAssertEqual(anchors.right.cyl.midX, 790, accuracy: 40)
    }

    func testAvgFallbackRoutesAvgsCorrectlyWhenOneEyesHeadersMissing() async {
        // Real-world degraded capture: dim thermal print leaves left-eye
        // SPH/CYL/AX headers undetected by ML Kit. With only right-eye
        // headers detected, the biggest-header-gap heuristic collapses to a
        // tiny cluster and both AVG bands fall below it — producing a
        // misleading "right AVG" missing error. AVG-to-AVG midpoint
        // fallback routes each AVG to the correct eye, so the resulting
        // throw correctly identifies the MISSING headers (left SPH/CYL/AX),
        // not a bogus right-AVG failure.
        var lines = fullLineSet()
        lines.removeAll { ["SPH", "CYL", "AX"].contains($0.text) && $0.frame.origin.y > 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        do {
            _ = try await detector.detectAnchors(in: blankImage())
            XCTFail("expected throw — left section has no column headers")
        } catch AnchorDetector.Error.insufficientAnchors(let missing) {
            // Error must cite left SPH/CYL/AX (root cause), NOT "right AVG"
            // (symptom from wrong split).
            XCTAssertTrue(missing.contains(where: { $0.contains("left") && $0.contains("SPH") }),
                          "expected missing to include 'left SPH', got \(missing)")
            XCTAssertFalse(missing.contains(where: { $0.contains("right AVG") }),
                           "fallback should not produce 'right AVG' error, got \(missing)")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testExcludesGlobalCylPolarityLabel() async throws {
        // The "VD = 0mm  CYL (-)" row at the top of the slip yields a CYL
        // token at a Y where no SPH/AX partner sits. The filter must drop
        // it so the section-split heuristic doesn't latch onto the spurious
        // top row.
        var lines = fullLineSet()
        // Inject a stray CYL token far above the right-eye headers and
        // with NO SPH/AX partner on its row.
        lines.append(OCRLine(text: "CYL", frame: CGRect(x: 800, y: 20, width: 80, height: 60)))
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        let anchors = try await detector.detectAnchors(in: blankImage())
        // Without filtering, the stray y=20 CYL would skew everything. If
        // section split is correct, right SPH should still resolve to y=160.
        XCTAssertEqual(anchors.right.sph.origin.y, 160)
        XCTAssertEqual(anchors.left.sph.origin.y, 760)
    }
}
