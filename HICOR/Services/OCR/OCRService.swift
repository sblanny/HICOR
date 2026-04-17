import Foundation
import UIKit

enum ReconstructionStrategy: String, Codable, Equatable {
    case row
    case column
}

struct VariantScore: Codable, Equatable {
    let variant: PreprocessingVariant
    let reconstruction: ReconstructionStrategy
    let revisionUsed: Int
    let validReadingCount: Int
    let sectionCompleteness: Double
    let markerContinuity: Double
    let avgConfidence: Double
    let totalScore: Double
    let parseErrorDescription: String?
}

struct OCRImageResult: Equatable {
    let photoIndex: Int
    let printout: PrintoutResult?
    let winningScore: VariantScore?
    let allScores: [VariantScore]
    let rawText: String
    let preprocessedImageData: Data?
    let extractionErrorDescription: String?
}

struct OCRBatchResult: Equatable {
    let perImage: [OCRImageResult]
    let debugSnapshot: OCRDebugSnapshot
    let overallError: OCRService.OCRError?

    var successfulResults: [PrintoutResult] {
        perImage.compactMap(\.printout)
    }
}

enum ParseScorer {
    static let wReadingCount: Double     = 0.50
    static let wSectionComplete: Double  = 0.25
    static let wMarkerContinuity: Double = 0.15
    static let wConfidence: Double       = 0.10
    static let shortCircuitThreshold: Double = 0.85

    static func score(
        result: PrintoutResult?,
        extraction: ExtractedText,
        reconstruction: ReconstructionStrategy
    ) -> VariantScore {
        let readings = (result?.rightEye?.readings.count ?? 0) + (result?.leftEye?.readings.count ?? 0)
        let readingScore = min(Double(readings), 12.0) / 12.0

        let rightHas = (result?.rightEye?.readings.isEmpty == false)
        let leftHas  = (result?.leftEye?.readings.isEmpty  == false)
        let completeness = (rightHas ? 0.5 : 0.0) + (leftHas ? 0.5 : 0.0)

        let blob = (extraction.rowBased + extraction.columnBased).joined(separator: " ").uppercased()
        let hasR = blob.contains("[R]") || blob.contains("<R>")
        let hasL = blob.contains("[L]") || blob.contains("<L>")
        let hasSignal = blob.contains("*") || blob.contains("AVG") || blob.contains("-REF-")
        let markerCount = [hasR, hasL, hasSignal].filter { $0 }.count
        let markerContinuity = Double(markerCount) / 3.0

        let confidence = averageConfidence(result: result, extraction: extraction)

        let total = wReadingCount * readingScore
                  + wSectionComplete * completeness
                  + wMarkerContinuity * markerContinuity
                  + wConfidence * confidence

        return VariantScore(
            variant: extraction.variant,
            reconstruction: reconstruction,
            revisionUsed: extraction.revisionUsed,
            validReadingCount: readings,
            sectionCompleteness: completeness,
            markerContinuity: markerContinuity,
            avgConfidence: confidence,
            totalScore: total,
            parseErrorDescription: result == nil ? "parse failed" : nil
        )
    }

    private static func averageConfidence(result: PrintoutResult?, extraction: ExtractedText) -> Double {
        guard let printout = result, !extraction.boxes.isEmpty else { return 0.0 }
        let readings = (printout.rightEye?.readings ?? []) + (printout.leftEye?.readings ?? [])
        guard !readings.isEmpty else { return 0.0 }
        let accepted = extraction.boxes.filter { box in
            let tokens = box.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return readings.contains { rr in
                let sph = String(format: "%.2f", rr.sph)
                let cyl = String(format: "%.2f", rr.cyl)
                let ax = String(rr.ax)
                return box.text.contains(sph)
                    || box.text.contains(cyl)
                    || tokens.contains(ax)
            }
        }
        guard !accepted.isEmpty else { return 0.0 }
        let mean = accepted.map { Double($0.confidence) }.reduce(0, +) / Double(accepted.count)
        return max(0.0, min(1.0, mean))
    }
}

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

        if rowAttempt == nil && colAttempt == nil {
            throw OCRError.unrecognizedFormat
        }
        throw OCRError.insufficientReadings
    }

    static func readingCount(_ result: PrintoutResult) -> Int {
        (result.rightEye?.readings.count ?? 0) + (result.leftEye?.readings.count ?? 0)
    }
}
