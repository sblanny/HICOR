import XCTest
import UIKit
@testable import HICOR

private struct PassthroughRecognizer: LineRecognizing {
    let lines: [OCRLine]
    init(lines: [OCRLine] = []) { self.lines = lines }
    func recognize(_ image: UIImage) async throws -> [OCRLine] { lines }
}

/// Stubs everything the orchestrator calls through: rectifier, enhancer,
/// anchor detector, per-cell OCR, fallback extractor.
private final class StubAnchorDetector: AnchorDetector {
    let result: Result<Anchors, Error>
    init(result: Result<Anchors, Error>) {
        self.result = result
        super.init(recognizer: PassthroughRecognizer())
    }
    override func detectAnchors(in image: UIImage) async throws -> Anchors {
        switch result {
        case .success(let a): return a
        case .failure(let e): throw e
        }
    }
    override func detectAnchors(from lines: [OCRLine]) throws -> Anchors {
        switch result {
        case .success(let a): return a
        case .failure(let e): throw e
        }
    }
}

private final class ScriptedCellOCR: CellOCR {
    let table: [CellROI: String?]
    init(table: [CellROI: String?]) {
        self.table = table
        super.init(recognizer: PassthroughRecognizer())
    }
    override func read(cell: CellROI, image: UIImage) async -> String? {
        table[cell] ?? nil
    }
}

private final class StubFallback: TextExtracting {
    let output: ExtractedText
    private(set) var callCount = 0
    init(output: ExtractedText) { self.output = output }
    func extractText(from image: UIImage) async throws -> ExtractedText {
        callCount += 1
        return output
    }
}

final class ROIPipelineExtractorTests: XCTestCase {

    private func blankImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1100)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1100))
        }
    }

    private func syntheticAnchors() -> Anchors {
        let right = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y:  60, width: 60, height: 60),
            sph: CGRect(x: 120, y: 100, width: 80, height: 60),
            cyl: CGRect(x: 120, y: 240, width: 80, height: 60),
            ax:  CGRect(x: 120, y: 380, width: 80, height: 60),
            avg: CGRect(x: 120, y: 520, width: 80, height: 60))
        let left = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y: 640, width: 60, height: 60),
            sph: CGRect(x: 120, y: 680, width: 80, height: 60),
            cyl: CGRect(x: 120, y: 800, width: 80, height: 60),
            ax:  CGRect(x: 120, y: 920, width: 80, height: 60),
            avg: CGRect(x: 120, y:1040, width: 80, height: 60))
        return Anchors(right: right, left: left)
    }

    /// Build the 24-cell value table so every cell reads a known value.
    private func fullCellTable(anchors: Anchors) -> [CellROI: String?] {
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        var table: [CellROI: String?] = [:]
        for cell in cells {
            switch cell.column {
            case .sph: table[cell] = "-1.25"
            case .cyl: table[cell] = "0.25"
            case .ax:  table[cell] = "92"
            }
        }
        return table
    }

    private func fallbackDesktopOutput() -> ExtractedText {
        ExtractedText(
            rowBased: [
                "[R]",
                "+1.00 -0.50 108",
                "+1.25 -0.50 110",
                "+0.75 -0.25 104",
                "AVG +1.00 -0.50 107",
                "[L]",
                "+0.75 -2.50 9",
                "+2.00 -2.00 6",
                "+2.00 -2.75 27",
                "AVG +1.50 -2.50 15"
            ],
            columnBased: []
        )
    }

    func testHappyPathProducesRowBasedLines() async throws {
        let anchors = syntheticAnchors()
        let extractor = ROIPipelineExtractor(
            rectify: { _ in self.blankImage() },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: fullCellTable(anchors: anchors)),
            fallback: StubFallback(output: .empty)
        )
        let text = try await extractor.extractText(from: blankImage())
        XCTAssertTrue(text.rowBased.contains("[R]"))
        XCTAssertTrue(text.rowBased.contains("[L]"))
        XCTAssertTrue(text.rowBased.contains("-1.25 -0.25 92"))
        XCTAssertTrue(text.rowBased.contains("AVG -1.25 -0.25 92"))
    }

    func testFallbackStillThrowsWhenFallbackParseIsIncomplete() async throws {
        let fallback = StubFallback(output: ExtractedText(
            rowBased: ["[R]", "-1.25 -0.50 108"], columnBased: []))
        let extractor = ROIPipelineExtractor(
            rectify: { _ in nil },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(
                result: .failure(AnchorDetector.Error.insufficientAnchors(missing: []))),
            cellOCR: ScriptedCellOCR(table: [:]),
            fallback: fallback
        )
        do {
            _ = try await extractor.extractText(from: blankImage())
            XCTFail("expected incomplete-cells throw (fallback lacks full cell set)")
        } catch OCRService.OCRError.incompleteCells {
            XCTAssertEqual(fallback.callCount, 1)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAnchorThrowUsesFallbackWhenParserCanRecoverFullGrid() async throws {
        let fallback = StubFallback(output: fallbackDesktopOutput())
        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(
                result: .failure(AnchorDetector.Error.insufficientAnchors(missing: ["right SPH"]))),
            cellOCR: ScriptedCellOCR(table: [:]),
            fallback: fallback
        )
        let text = try await extractor.extractText(from: blankImage())
        XCTAssertEqual(fallback.callCount, 1)
        XCTAssertTrue(text.rowBased.contains("AVG +1.00 -0.50 107"))
        XCTAssertTrue(text.rowBased.contains("AVG +1.50 -2.50 15"))
    }

    func testAnyMissingCellThrowsIncompleteCells() async {
        let anchors = syntheticAnchors()
        var table = fullCellTable(anchors: anchors)
        // Drop a single cell → nil.
        let firstKey = table.first { $0.value != nil }!.key
        table[firstKey] = .some(nil)

        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: table),
            fallback: StubFallback(output: .empty)
        )
        do {
            _ = try await extractor.extractText(from: blankImage())
            XCTFail("expected throw")
        } catch OCRService.OCRError.incompleteCells(let missing) {
            XCTAssertFalse(missing.isEmpty)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testSectionSignInferenceRequiresTwoDirectPeers() async throws {
        let anchors = syntheticAnchors()
        var table = fullCellTable(anchors: anchors)
        let rightRows = CellLayout.grk6000Desktop
            .cells(given: anchors)
            .filter { $0.eye == .right && $0.column == .sph }
        for cell in rightRows {
            table[cell] = "1.25"
        }
        table[rightRows.first { $0.row == .r1 }!] = "+1.25"

        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: table),
            fallback: StubFallback(output: .empty)
        )

        let text = try await extractor.extractText(from: blankImage())
        XCTAssertEqual(text.rowBased[2], "1.25 -0.25 92")
        XCTAssertEqual(text.rowBased[3], "1.25 -0.25 92")
    }

    func testSectionSignInferenceUsesStrongConsensusOnly() async throws {
        let anchors = syntheticAnchors()
        var table = fullCellTable(anchors: anchors)
        let rightRows = CellLayout.grk6000Desktop
            .cells(given: anchors)
            .filter { $0.eye == .right && $0.column == .sph }
        for cell in rightRows {
            table[cell] = "1.25"
        }
        table[rightRows.first { $0.row == .r1 }!] = "+1.25"
        table[rightRows.first { $0.row == .r3 }!] = "+1.25"

        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            lineRecognizer: PassthroughRecognizer(),
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: table),
            fallback: StubFallback(output: .empty)
        )

        let text = try await extractor.extractText(from: blankImage())
        XCTAssertEqual(text.rowBased[2], "+1.25 -0.25 92")
        XCTAssertEqual(text.rowBased[4], "+1.25 -0.25 92")
    }
}
