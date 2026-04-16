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

    func testProcessImagesParsesDesktopFixtureViaStubExtractor() async throws {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: OCRFixture.load("desktop_standard"), columnBased: [])]
        let service = OCRService(extractor: stub)

        let results = try await service.processImages([UIImage()])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].machineType, .desktop)
        XCTAssertEqual(results[0].rightEye?.readings.count, 3)
        XCTAssertEqual(results[0].pd, 64.0)
    }

    func testGarbageInputThrowsUnrecognizedFormat() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: ["random", "noise", "nothing useful"], columnBased: [])]
        let service = OCRService(extractor: stub)

        do {
            _ = try await service.processImages([UIImage()])
            XCTFail("Expected throw")
        } catch let error as OCRService.OCRError {
            XCTAssertEqual(error, .unrecognizedFormat)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInsufficientReadingsThrownWhenBothEyesEmpty() async {
        // Handheld format recognized (-REF- present) but both eye sections empty.
        let emptyHandheld = ["No. 099", "VD: 13.5", "-REF-", "[R]", "[L]"]
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: emptyHandheld, columnBased: emptyHandheld)]
        let service = OCRService(extractor: stub)

        do {
            _ = try await service.processImages([UIImage()])
            XCTFail("Expected throw")
        } catch let error as OCRService.OCRError {
            XCTAssertEqual(error, .insufficientReadings)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testColumnBasedFallbackUsedWhenRowBasedYieldsNothing() async throws {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(
            rowBased: ["completely garbled column-fragmented junk"],
            columnBased: OCRFixture.load("desktop_standard")
        )]
        let service = OCRService(extractor: stub)

        let results = try await service.processImages([UIImage()])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].machineType, .desktop)
        XCTAssertEqual(results[0].rightEye?.readings.count, 3)
    }
}
