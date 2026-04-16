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

    func processImage(_ image: UIImage, photoIndex: Int = 0) async throws -> PrintoutResult {
        let lines = try await extractor.extractText(from: image)
        guard !lines.isEmpty else { throw OCRError.noTextFound }
        return try PrintoutParser.parse(lines: lines, photoIndex: photoIndex)
    }

    func processImages(_ images: [UIImage]) async throws -> [PrintoutResult] {
        var results: [PrintoutResult] = []
        for (index, image) in images.enumerated() {
            let result = try await processImage(image, photoIndex: index)
            results.append(result)
        }
        return results
    }
}
