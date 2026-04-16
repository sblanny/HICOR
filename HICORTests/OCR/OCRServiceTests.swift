import XCTest
import UIKit
@testable import HICOR

final class StubExtractor: TextExtracting {
    var nextLines: [[String]] = []
    func extractText(from image: UIImage) async throws -> [String] {
        guard !nextLines.isEmpty else { return [] }
        return nextLines.removeFirst()
    }
}

final class OCRServiceTests: XCTestCase {

    func testProcessImagesParsesDesktopFixtureViaStubExtractor() async throws {
        let stub = StubExtractor()
        stub.nextLines = [OCRFixture.load("desktop_standard")]
        let service = OCRService(extractor: stub)

        let results = try await service.processImages([UIImage()])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].machineType, .desktop)
        XCTAssertEqual(results[0].rightEye?.readings.count, 3)
        XCTAssertEqual(results[0].pd, 64.0)
    }

    func testGarbageInputThrowsUnrecognizedFormat() async {
        let stub = StubExtractor()
        stub.nextLines = [["random", "noise", "nothing useful"]]
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
}
