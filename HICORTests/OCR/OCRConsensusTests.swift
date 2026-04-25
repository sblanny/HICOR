import XCTest
import UIKit
@testable import HICOR

/// Stub extractor that returns pre-programmed PartialCellExtraction
/// results per call. Drives the consensus merge tests without invoking
/// real MLKit/Vision OCR.
private final class ConsensusStubExtractor: TextExtracting {
    var nextPartials: [PartialCellExtraction] = []
    var nextErrors: [Error?] = []

    func extractText(from image: UIImage) async throws -> ExtractedText {
        throw OCRService.OCRError.unrecognizedFormat
    }

    func extractCellValues(from image: UIImage) async throws -> PartialCellExtraction {
        if !nextErrors.isEmpty, let error = nextErrors.removeFirst() {
            throw error
        }
        guard !nextPartials.isEmpty else {
            throw OCRService.OCRError.unrecognizedFormat
        }
        return nextPartials.removeFirst()
    }
}

final class OCRConsensusTests: XCTestCase {

    func testConsensusSucceedsWithSingleCompletePhoto() async {
        let stub = ConsensusStubExtractor()
        stub.nextPartials = [Self.makePartial(full: true)]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage()])

        XCTAssertEqual(result.missingCells, [])
        XCTAssertEqual(result.perImage.count, 1, "Single complete photo yields one merged PrintoutResult")
        XCTAssertTrue(result.disagreements.isEmpty, "No disagreements with a single photo")
        XCTAssertEqual(result.perImage[0].rightEye?.readings.count, 3)
        XCTAssertEqual(result.perImage[0].leftEye?.readings.count, 3)
    }

    func testConsensusFillsMissingCellFromAnotherPhoto() async {
        // Photo 0 missing right ax r1; photo 1 has it. Majority of votes
        // for that cell: just photo 1. Winner: photo 1's value.
        var photo0 = Self.makeFullValuesMap()
        photo0.removeValue(forKey: Self.cell(.right, .ax, .r1))
        let photo1 = Self.makeFullValuesMap()

        let stub = ConsensusStubExtractor()
        stub.nextPartials = [
            Self.makePartial(values: photo0, missing: ["right ax r1"]),
            Self.makePartial(values: photo1, missing: [])
        ]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage()])
        XCTAssertEqual(result.missingCells, [])
        XCTAssertEqual(result.perImage.count, 1, "Merged result is a single PrintoutResult")
        XCTAssertTrue(result.disagreements.isEmpty, "Photo 0 had nil — no conflicting votes, only borrow")
    }

    func testConsensusReportsCellsMissingEverywhere() async {
        var photo0 = Self.makeFullValuesMap()
        photo0.removeValue(forKey: Self.cell(.right, .ax, .r1))
        var photo1 = Self.makeFullValuesMap()
        photo1.removeValue(forKey: Self.cell(.right, .ax, .r1))

        let stub = ConsensusStubExtractor()
        stub.nextPartials = [
            Self.makePartial(values: photo0, missing: ["right ax r1"]),
            Self.makePartial(values: photo1, missing: ["right ax r1"])
        ]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage()])
        XCTAssertEqual(result.missingCells, ["right ax r1"])
        XCTAssertEqual(result.perImage.count, 0)
    }

    func testConsensusSkipsPhotosThatFailAnchorDetection() async {
        let stub = ConsensusStubExtractor()
        stub.nextErrors = [OCRService.OCRError.incompleteCells(missing: ["anchor detection failed"]), nil]
        stub.nextPartials = [Self.makePartial(full: true)]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage()])
        XCTAssertEqual(result.missingCells, [])
        XCTAssertEqual(result.perImage.count, 1, "Photo 0 excluded by anchor failure; photo 1 carried the set")
    }

    func testConsensusAllPhotosFailSurfacesRecaptureError() async {
        let stub = ConsensusStubExtractor()
        stub.nextErrors = [
            OCRService.OCRError.incompleteCells(missing: ["anchor detection failed"]),
            OCRService.OCRError.incompleteCells(missing: ["anchor detection failed"])
        ]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage()])
        XCTAssertEqual(result.perImage.count, 0)
        XCTAssertEqual(result.missingCells, ["no readable photo — recapture required"])
    }

    func testMajorityVoteWinsOverMinority() async {
        // This is the scenario from the real-world bug report: one photo
        // has an OCR misread on a CYL cell that produces "9.50" while
        // the other two photos correctly read "2.50". Under first-wins,
        // "9.50" would survive. Under majority, "2.50" wins.
        var photoBad = Self.makeFullValuesMap()
        photoBad[Self.cell(.left, .cyl, .r2)] = "-9.50"
        var photoGood1 = Self.makeFullValuesMap()
        photoGood1[Self.cell(.left, .cyl, .r2)] = "-2.50"
        var photoGood2 = Self.makeFullValuesMap()
        photoGood2[Self.cell(.left, .cyl, .r2)] = "-2.50"

        let stub = ConsensusStubExtractor()
        stub.nextPartials = [
            Self.makePartial(values: photoBad, missing: []),
            Self.makePartial(values: photoGood1, missing: []),
            Self.makePartial(values: photoGood2, missing: [])
        ]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage(), UIImage()])

        XCTAssertEqual(result.perImage.count, 1)
        let merged = result.perImage[0]
        let r2 = merged.leftEye?.readings[safe: 1]
        XCTAssertEqual(r2?.cyl, -2.50, "Majority (2 photos) beats the first photo's misread")

        // Disagreement must be surfaced (memory requires auto-picks to be visible).
        XCTAssertFalse(result.disagreements.isEmpty, "Disagreement must be recorded for the operator")
        let disagreement = result.disagreements.first { $0.cellLabel == "left cyl r2" }
        XCTAssertNotNil(disagreement)
        XCTAssertEqual(disagreement?.votes.first?.value, "-2.50", "Winning value listed first")
        XCTAssertEqual(disagreement?.votes.first?.photoIndices.count, 2)
    }

    func testTieBreakerPrefersEarliestPhoto() async {
        // 2-way tie (1 vote each). Whichever value's earliest-voting
        // photo came first in capture order wins. Locks in deterministic
        // behavior so future refactors don't silently change the outcome.
        var photoA = Self.makeFullValuesMap()
        photoA[Self.cell(.right, .sph, .r1)] = "+1.25"
        var photoB = Self.makeFullValuesMap()
        photoB[Self.cell(.right, .sph, .r1)] = "+1.50"

        let stub = ConsensusStubExtractor()
        stub.nextPartials = [
            Self.makePartial(values: photoA, missing: []),
            Self.makePartial(values: photoB, missing: [])
        ]
        let service = OCRService(extractor: stub)

        let result = await service.processImagesWithConsensus([UIImage(), UIImage()])
        let r1 = result.perImage[0].rightEye?.readings[safe: 0]
        XCTAssertEqual(r1?.sph, 1.25, "Tie broken by earliest-voting photo (photo 0's value)")
        XCTAssertFalse(result.disagreements.isEmpty, "Ties still count as disagreements")
    }

    // MARK: - Fixture helpers

    private static func cell(_ eye: CellROI.Eye, _ column: CellROI.Column, _ row: CellROI.Row) -> CellROI {
        CellROI(eye: eye, column: column, row: row, rect: .zero)
    }

    private static func makeFullValuesMap() -> [CellROI: String] {
        var values: [CellROI: String] = [:]
        for eye in [CellROI.Eye.right, .left] {
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                values[cell(eye, .sph, row)] = "+1.00"
                values[cell(eye, .cyl, row)] = "-1.00"
                values[cell(eye, .ax,  row)] = "90"
            }
        }
        return values
    }

    private static func makeCatalog() -> [CellROI] {
        var cells: [CellROI] = []
        for eye in [CellROI.Eye.right, .left] {
            for column in [CellROI.Column.sph, .cyl, .ax] {
                for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                    cells.append(cell(eye, column, row))
                }
            }
        }
        return cells
    }

    private static func makePartial(full: Bool) -> PartialCellExtraction {
        PartialCellExtraction(
            values: full ? makeFullValuesMap() : [:],
            cells: makeCatalog(),
            missing: full ? [] : makeCatalog().map { "\($0.eye.rawValue) \($0.column.rawValue) \($0.row.rawValue)" },
            preprocessedImageData: nil
        )
    }

    private static func makePartial(values: [CellROI: String], missing: [String]) -> PartialCellExtraction {
        PartialCellExtraction(
            values: values,
            cells: makeCatalog(),
            missing: missing,
            preprocessedImageData: nil
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
