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

    func testPipelineScoresAcrossVariantsAndPicksBest() async {
        final class MultiVariantStub: TextExtracting {
            var calls: [(PreprocessingVariant, Int)] = []
            func extractText(from image: UIImage) async throws -> ExtractedText {
                try await extractText(from: image, variant: .standard, revision: VisionTextExtractor.latestRevision())
            }
            func extractText(from image: UIImage, variant: PreprocessingVariant, revision: Int) async throws -> ExtractedText {
                calls.append((variant, revision))
                switch variant {
                case .standard:
                    return ExtractedText(
                        rowBased: ["garbage"], columnBased: [],
                        preprocessedImageData: nil, boxes: [],
                        revisionUsed: revision, variant: variant
                    )
                case .thermalBinary:
                    return ExtractedText(
                        rowBased: OCRFixture.load("desktop_standard"), columnBased: [],
                        preprocessedImageData: nil, boxes: [],
                        revisionUsed: revision, variant: variant
                    )
                case .raw:
                    return ExtractedText(
                        rowBased: ["garbage"], columnBased: [],
                        preprocessedImageData: nil, boxes: [],
                        revisionUsed: revision, variant: variant
                    )
                }
            }
        }
        let stub = MultiVariantStub()
        let service = OCRService(extractor: stub)
        let batch = await service.processImages([UIImage()])
        XCTAssertEqual(batch.perImage[0].winningScore?.variant, .thermalBinary)
        XCTAssertGreaterThanOrEqual(stub.calls.count, 2)
    }
}
