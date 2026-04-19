import XCTest
import UIKit
@testable import HICOR

final class StubExtractor: TextExtracting {
    var nextResults: [ExtractedText] = []
    func extractText(from image: UIImage) async throws -> ExtractedText {
        guard !nextResults.isEmpty else { return .empty }
        return nextResults.removeFirst()
    }
}

final class OCRServiceTests: XCTestCase {

    func testProcessImagesReturnsBatchWithDesktopResult() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: OCRFixture.load("desktop_standard"), columnBased: [])]
        let service = OCRService(extractor: stub)

        let batch = await service.processImages([UIImage()])
        XCTAssertNil(batch.overallError)
        XCTAssertEqual(batch.successfulResults.count, 1)
        XCTAssertEqual(batch.successfulResults[0].machineType, .desktop)
        XCTAssertEqual(batch.successfulResults[0].rightEye?.readings.count, 3)
        XCTAssertEqual(batch.successfulResults[0].pd, 64.0)
        XCTAssertNotNil(batch.perImage[0].winningScore)
    }

    func testBatchOverallErrorSetToUnrecognizedFormatOnGarbage() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: ["random", "noise", "nothing useful"], columnBased: ["random", "noise"])]
        let service = OCRService(extractor: stub)

        let batch = await service.processImages([UIImage()])
        XCTAssertNil(batch.perImage[0].printout)
        XCTAssertEqual(batch.overallError, .unrecognizedFormat)
    }

    func testBatchOverallErrorSetToInsufficientReadingsWhenFormatRecognizedButEmpty() async {
        let emptyHandheld = ["No. 099", "VD: 13.5", "-REF-", "[R]", "[L]"]
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: emptyHandheld, columnBased: emptyHandheld)]
        let service = OCRService(extractor: stub)

        let batch = await service.processImages([UIImage()])
        XCTAssertNil(batch.perImage[0].printout)
        XCTAssertEqual(batch.overallError, .insufficientReadings)
        XCTAssertNil(batch.perImage[0].winningScore?.parseErrorDescription,
                     "Expected format recognized (parse succeeded with zero readings), got parse failure")
        XCTAssertEqual(batch.perImage[0].winningScore?.validReadingCount, 0)
    }

    func testColumnBasedFallbackUsedWhenRowBasedYieldsNothing() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(
            rowBased: ["completely garbled row junk"],
            columnBased: OCRFixture.load("desktop_standard")
        )]
        let service = OCRService(extractor: stub)

        let batch = await service.processImages([UIImage()])
        XCTAssertNil(batch.overallError)
        XCTAssertEqual(batch.successfulResults.count, 1)
        XCTAssertEqual(batch.successfulResults[0].machineType, .desktop)
        XCTAssertEqual(batch.successfulResults[0].rightEye?.readings.count, 3)
    }

    func testPipelineCallsExtractorOnceAndPicksHigherScoringReconstruction() async {
        final class CallCountingStub: TextExtracting {
            var callCount = 0
            func extractText(from image: UIImage) async throws -> ExtractedText {
                callCount += 1
                // row reconstruction parses to a clean desktop printout (high score),
                // column reconstruction is garbage (low score).
                return ExtractedText(
                    rowBased: OCRFixture.load("desktop_standard"),
                    columnBased: ["random", "garbage"]
                )
            }
        }
        let stub = CallCountingStub()
        let service = OCRService(extractor: stub)

        let batch = await service.processImages([UIImage()])
        XCTAssertEqual(stub.callCount, 1,
                       "Pipeline collapsed to single pass — extractor should be called exactly once per image")
        XCTAssertEqual(batch.perImage[0].winningScore?.reconstruction, .row)
        XCTAssertEqual(batch.successfulResults.count, 1)
        XCTAssertEqual(batch.perImage[0].allScores.count, 2,
                       "Expected scores for both row and column reconstructions")
    }
}
