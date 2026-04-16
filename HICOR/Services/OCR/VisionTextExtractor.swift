import Foundation
import UIKit
import Vision

protocol TextExtracting {
    func extractText(from image: UIImage) async throws -> [String]
}

enum VisionTextExtractorError: Error {
    case missingCGImage
    case visionFailed(Error)
}

final class VisionTextExtractor: TextExtracting {

    func extractText(from image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw VisionTextExtractorError.missingCGImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionTextExtractorError.visionFailed(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted { lhs, rhs in
                        let dy = rhs.boundingBox.minY - lhs.boundingBox.minY
                        if abs(dy) > 0.01 {
                            return lhs.boundingBox.minY > rhs.boundingBox.minY
                        }
                        return lhs.boundingBox.minX < rhs.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionTextExtractorError.visionFailed(error))
            }
        }
    }
}
