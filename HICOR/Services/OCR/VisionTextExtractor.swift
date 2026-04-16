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

    private let rowTolerance: CGFloat = 0.02

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
                let lines = self.reconstructRows(from: observations)
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

    private func reconstructRows(from observations: [VNRecognizedTextObservation]) -> [String] {
        var rows: [[VNRecognizedTextObservation]] = []
        for obs in observations {
            let y = obs.boundingBox.midY
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.boundingBox.midY - y) < rowTolerance
            }) {
                rows[rowIndex].append(obs)
            } else {
                rows.append([obs])
            }
        }

        rows.sort { lhs, rhs in
            guard let l = lhs.first, let r = rhs.first else { return false }
            return l.boundingBox.midY > r.boundingBox.midY
        }

        return rows.map { row -> String in
            let sorted = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let texts = sorted.compactMap { $0.topCandidates(1).first?.string }
            return texts.joined(separator: "  ")
        }
    }
}
