import Foundation
import UIKit

@Observable
final class OCRService {

    enum OCRError: Error, Equatable {
        case noTextFound
        case unrecognizedFormat
        case insufficientReadings
    }

    private let extractor: TextExtracting

    init(extractor: TextExtracting = VisionTextExtractor()) {
        self.extractor = extractor
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        try await extractor.extractText(from: image)
    }

    func processImage(_ image: UIImage, photoIndex: Int = 0) async throws -> PrintoutResult {
        let extracted = try await extractor.extractText(from: image)
        return try Self.parseBest(from: extracted, photoIndex: photoIndex)
    }

    func processImages(_ images: [UIImage]) async throws -> [PrintoutResult] {
        var results: [PrintoutResult] = []
        for (index, image) in images.enumerated() {
            let result = try await processImage(image, photoIndex: index)
            results.append(result)
        }
        return results
    }

    static func parseBest(from extracted: ExtractedText, photoIndex: Int) throws -> PrintoutResult {
        if extracted.rowBased.isEmpty && extracted.columnBased.isEmpty {
            throw OCRError.noTextFound
        }

        let rowAttempt = try? PrintoutParser.parse(lines: extracted.rowBased, photoIndex: photoIndex)
        if let r = rowAttempt, readingCount(r) > 0 {
            return r
        }

        let colAttempt = try? PrintoutParser.parse(lines: extracted.columnBased, photoIndex: photoIndex)
        if let c = colAttempt, readingCount(c) > 0 {
            return c
        }

        if let r = rowAttempt { return r }
        if let c = colAttempt { return c }
        throw OCRError.unrecognizedFormat
    }

    static func readingCount(_ result: PrintoutResult) -> Int {
        (result.rightEye?.readings.count ?? 0) + (result.leftEye?.readings.count ?? 0)
    }
}
