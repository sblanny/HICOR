import XCTest
import UIKit
@testable import HICOR

final class OCRSingleValidationTests: XCTestCase {

    func testRunSingleReturnsNilForInvalidImageData() async {
        let service = OCRService(extractor: StubExtractor())
        let result = await service.runSingle(imageData: Data([0x00, 0x01, 0x02]))
        XCTAssertNil(result, "Invalid image bytes should yield nil, not throw")
    }

    func testRunSingleReturnsNilWhenExtractionYieldsGarbage() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(
            rowBased: ["random", "noise", "nothing useful"],
            columnBased: ["random", "noise"]
        )]
        let service = OCRService(extractor: stub)

        let data = Self.makeJpegData()
        let result = await service.runSingle(imageData: data)
        XCTAssertNil(result, "Unrecognized format should yield nil — caller rejects the photo")
    }

    func testRunSingleReturnsPrintoutOnSuccessfulExtraction() async {
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(
            rowBased: OCRFixture.load("desktop_standard"),
            columnBased: []
        )]
        let service = OCRService(extractor: stub)

        let data = Self.makeJpegData()
        let result = await service.runSingle(imageData: data)
        XCTAssertNotNil(result, "Recognizable printout must return a non-nil PrintoutResult")
        XCTAssertEqual(result?.machineType, .desktop)
        XCTAssertEqual(result?.rightEye?.readings.count, 3)
    }

    func testRunSingleReturnsNilWhenFormatRecognizedButNoReadings() async {
        let emptyHandheld = ["No. 099", "VD: 13.5", "-REF-", "[R]", "[L]"]
        let stub = StubExtractor()
        stub.nextResults = [ExtractedText(rowBased: emptyHandheld, columnBased: emptyHandheld)]
        let service = OCRService(extractor: stub)

        let data = Self.makeJpegData()
        let result = await service.runSingle(imageData: data)
        XCTAssertNil(result, "Empty-readings printouts should be rejected — nothing usable to save")
    }

    private static func makeJpegData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        return img.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
