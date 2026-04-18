import XCTest
import UIKit
@testable import HICOR

/// Stub that returns different lines on first vs. second call.
private final class ScriptedRecognizer: LineRecognizing {
    var scripted: [[OCRLine]]
    private(set) var callCount = 0
    init(scripted: [[OCRLine]]) { self.scripted = scripted }
    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        defer { callCount += 1 }
        let idx = min(callCount, scripted.count - 1)
        return scripted[idx]
    }
}

final class CellOCRTests: XCTestCase {

    private func dummyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
    }

    private func cell(_ col: CellROI.Column) -> CellROI {
        CellROI(eye: .right, column: col, row: .r1, rect: CGRect(x: 0, y: 0, width: 60, height: 40))
    }

    func testSPHCellAcceptsSignedDecimal() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "-1.25", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-1.25")
        XCTAssertEqual(recognizer.callCount, 1)
    }

    func testCYLCellAcceptsUnsignedDecimal() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "0.50", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.cyl), image: dummyImage())
        XCTAssertEqual(value, "0.50")
    }

    func testAXCellAcceptsIntegerInRange() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "92", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.ax), image: dummyImage())
        XCTAssertEqual(value, "92")
    }

    func testAXCellRejectsValueOutsideRange() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [OCRLine(text: "999", frame: .zero)],  // first attempt fails shape
            [OCRLine(text: "999", frame: .zero)]   // retry also fails
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.ax), image: dummyImage())
        XCTAssertNil(value)
        XCTAssertEqual(recognizer.callCount, 2, "should retry once then give up")
    }

    func testRetryOnInitialShapeFailSucceeds() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [OCRLine(text: "garbage", frame: .zero)],
            [OCRLine(text: "+1.00",   frame: .zero)]
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "+1.00")
        XCTAssertEqual(recognizer.callCount, 2)
    }

    func testPrefersHighestConfidenceLineWithValidShape() async {
        // ML Kit sometimes emits multiple lines for a cell; the implementation
        // should prefer the first one that passes shape validation.
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "junk", frame: .zero),
            OCRLine(text: "-2.25", frame: .zero),
            OCRLine(text: "also-junk", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-2.25")
        XCTAssertEqual(recognizer.callCount, 1, "no retry needed")
    }

    func testEmptyResultTriggersRetry() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [],
            [OCRLine(text: "-0.25", frame: .zero)]
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-0.25")
        XCTAssertEqual(recognizer.callCount, 2)
    }
}
