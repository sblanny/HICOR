import XCTest
import UIKit
@testable import HICOR

private struct PassthroughRecognizer: LineRecognizing {
    let lines: [OCRLine]
    init(lines: [OCRLine] = []) { self.lines = lines }
    func recognize(_ image: UIImage) async throws -> [OCRLine] { lines }
}

/// Returns different OCRLines depending on the image size. Used to simulate
/// the real-capture failure mode where the standard-enhanced image loses
/// thin minus-sign strokes that the raw image preserves.
private struct SizeDispatchRecognizer: LineRecognizing {
    let rawLines: [OCRLine]
    let standardLines: [OCRLine]
    let aggressiveLines: [OCRLine]
    let standardSize: CGSize
    let aggressiveSize: CGSize
    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        if image.size == standardSize { return standardLines }
        if image.size == aggressiveSize { return aggressiveLines }
        return rawLines
    }
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

    /// Real-capture regression: on dim thermal prints, the standard
    /// enhancement variant (gamma 0.7 + contrast 1.3 + unsharp) erases the
    /// thin "-" strokes printed in a sign column to the left of each SPH
    /// value. The standard variant typically wins on overall digit-recognition
    /// quality, so without intervention `applySignConventions` runs against
    /// sign-stripped lines and the values come out positive. This test
    /// asserts that sign reconciliation runs against the un-enhanced raw
    /// image's lines (which preserve the strokes), so the final values are
    /// signed correctly even when the winning variant lacks them.
    func testStandardVariantWithMissingSignsRecoversFromRawLines() async throws {
        let anchors = columnSpacedAnchors()
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        let rawSize = CGSize(width: 1500, height: 1100)
        let standardSize = CGSize(width: 1500, height: 1101)
        let aggressiveSize = CGSize(width: 1500, height: 1102)
        let rawImage = solidImage(size: rawSize)
        let standardImage = solidImage(size: standardSize)
        let aggressiveImage = solidImage(size: aggressiveSize)

        // Picker source: numeric values centered on each cell. Right eye SPH
        // is positive (2.50), left eye SPH is the value we want to recover as
        // negative ("2.00" with a separate "-" only present in rawLines).
        let valueLines = cells.map { cell -> OCRLine in
            let value: String
            switch (cell.eye, cell.column) {
            case (.right, .sph): value = "2.50"
            case (.right, .cyl): value = "1.00"
            case (.right, .ax):  value = "13"
            case (.left,  .sph): value = "2.00"
            case (.left,  .cyl): value = "1.75"
            case (.left,  .ax):  value = "172"
            }
            return OCRLine(
                text: value,
                frame: CGRect(
                    x: cell.rect.midX - 30,
                    y: cell.rect.midY - 15,
                    width: 60,
                    height: 30
                )
            )
        }

        // Raw-only addition: isolated "-" glyphs in the sign column to the
        // left of each LEFT eye SPH cell. Place them inside adjacentSign's
        // search window (one cell-width to the left of cell.rect.minX) but
        // outside pickCellValues' wideRect (cell.rect ± 30%) so they don't
        // alter the picked numeric value.
        let leftSPHCells = cells.filter { $0.eye == .left && $0.column == .sph }
        let signLines = leftSPHCells.map { cell in
            OCRLine(
                text: "-",
                frame: CGRect(
                    x: cell.rect.minX - cell.rect.width * 0.5 - 5,
                    y: cell.rect.midY - 3,
                    width: 10,
                    height: 6
                )
            )
        }

        let recognizer = SizeDispatchRecognizer(
            rawLines: valueLines + signLines,
            standardLines: valueLines,
            aggressiveLines: valueLines,
            standardSize: standardSize,
            aggressiveSize: aggressiveSize
        )

        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { _, strength in
                switch strength {
                case .standard: return standardImage
                case .aggressive: return aggressiveImage
                }
            },
            lineRecognizer: recognizer,
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: [:]),
            fallback: StubFallback(output: .empty)
        )

        let text = try await extractor.extractText(from: rawImage)

        // Right eye stays positive (no "-" glyphs in rawLines for that eye).
        XCTAssertTrue(text.rowBased.contains("[R]"))
        XCTAssertTrue(text.rowBased.contains("2.50 -1.00 13"))
        XCTAssertTrue(text.rowBased.contains("AVG 2.50 -1.00 13"))

        // Left eye SPH must come out negative on every row including AVG —
        // even though the standard variant's lines (which won the picking)
        // contained no "-" glyphs at all.
        XCTAssertTrue(text.rowBased.contains("[L]"))
        XCTAssertTrue(text.rowBased.contains("-2.00 -1.75 172"))
        XCTAssertTrue(text.rowBased.contains("AVG -2.00 -1.75 172"))
    }

    private func solidImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Anchors with SPH/CYL/AX headers spaced across X so each column's
    /// cells live in a distinct horizontal band — required for picker tests
    /// that exercise per-column line filtering.
    private func columnSpacedAnchors() -> Anchors {
        let right = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y:  60, width: 60, height: 60),
            sph: CGRect(x: 100, y: 100, width: 80, height: 60),
            cyl: CGRect(x: 250, y: 100, width: 80, height: 60),
            ax:  CGRect(x: 400, y: 100, width: 80, height: 60),
            avg: CGRect(x: 100, y: 520, width: 80, height: 60))
        let left = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y: 640, width: 60, height: 60),
            sph: CGRect(x: 100, y: 680, width: 80, height: 60),
            cyl: CGRect(x: 250, y: 680, width: 80, height: 60),
            ax:  CGRect(x: 400, y: 680, width: 80, height: 60),
            avg: CGRect(x: 100, y: 1040, width: 80, height: 60))
        return Anchors(right: right, left: left)
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
