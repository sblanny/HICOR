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
    let rowBasedLines: [String]
    let columnBasedLines: [String]
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
    // Weights shipped provisional 2026-04-16. No multi-patient calibration fixtures
    // existed at plan time; the only real debug logs were from one printout.
    // Validate empirically against ≥5 distinct-patient captures (May 1 trip) and
    // re-tune. Per-call logging in score(...) supports post-hoc calibration.
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

        print("ParseScorer: variant=\(extraction.variant.rawValue) reconstruction=\(reconstruction.rawValue) revision=\(extraction.revisionUsed) readings=\(readings) readingScore=\(String(format: "%.3f", readingScore)) completeness=\(completeness) markerContinuity=\(String(format: "%.3f", markerContinuity)) confidence=\(String(format: "%.3f", confidence)) total=\(String(format: "%.3f", total))")
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
        case incompleteCells(missing: [String])
    }

    private let extractor: TextExtracting

    init(extractor: TextExtracting = MLKitTextExtractor()) {
        self.extractor = extractor
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        try await extractor.extractText(from: image)
    }

    func processImage(_ image: UIImage, photoIndex: Int = 0) async throws -> PrintoutResult {
        let result = await runPipeline(image: image, photoIndex: photoIndex)
        if let printout = result.printout { return printout }
        throw Self.errorFor(result: result) ?? .unrecognizedFormat
    }

    func processImages(_ images: [UIImage]) async -> OCRBatchResult {
        var perImage: [OCRImageResult] = []
        var snapshotEntries: [OCRDebugSnapshot.Entry] = []
        var overallError: OCRError?

        for (index, image) in images.enumerated() {
            let imageResult = await runPipeline(image: image, photoIndex: index)
            perImage.append(imageResult)
            snapshotEntries.append(Self.buildDebugEntry(imageResult))
            if imageResult.printout == nil, overallError == nil {
                overallError = Self.errorFor(result: imageResult)
            }
        }

        let snapshot = OCRDebugSnapshot(
            entries: snapshotEntries,
            overallError: overallError.map { String(describing: $0) } ?? ""
        )
        return OCRBatchResult(
            perImage: perImage,
            debugSnapshot: snapshot,
            overallError: overallError
        )
    }

    private func runPipeline(image: UIImage, photoIndex: Int) async -> OCRImageResult {
        var allScores: [VariantScore] = []
        var winningScore: VariantScore?
        var winningPrintout: PrintoutResult?
        var extractionErrorDescription: String?

        let extracted: ExtractedText
        do {
            extracted = try await extractor.extractText(from: image)
        } catch {
            extractionErrorDescription = String(describing: error)
            return OCRImageResult(
                photoIndex: photoIndex,
                printout: nil,
                winningScore: nil,
                allScores: [],
                rawText: "",
                rowBasedLines: [],
                columnBasedLines: [],
                preprocessedImageData: nil,
                extractionErrorDescription: extractionErrorDescription
            )
        }

        for strategy in [ReconstructionStrategy.row, .column] {
            let lines = (strategy == .row) ? extracted.rowBased : extracted.columnBased
            let parsed = try? PrintoutParser.parse(lines: lines, photoIndex: photoIndex)
            let score = ParseScorer.score(result: parsed, extraction: extracted, reconstruction: strategy)
            allScores.append(score)
            if score.totalScore > (winningScore?.totalScore ?? -1.0) {
                winningScore = score
                winningPrintout = parsed
            }
        }

        let hasReadings: Bool = {
            guard let p = winningPrintout else { return false }
            return (p.rightEye?.readings.isEmpty == false) || (p.leftEye?.readings.isEmpty == false)
        }()
        let printoutIfUsable = hasReadings ? winningPrintout : nil

        print("OCRService: winning reconstruction=\(winningScore?.reconstruction.rawValue ?? "none") readings=\(winningScore?.validReadingCount ?? 0) score=\(winningScore?.totalScore ?? 0)")

        return OCRImageResult(
            photoIndex: photoIndex,
            printout: printoutIfUsable,
            winningScore: winningScore,
            allScores: allScores,
            rawText: (extracted.rowBased + extracted.columnBased).joined(separator: "\n"),
            rowBasedLines: extracted.rowBased,
            columnBasedLines: extracted.columnBased,
            preprocessedImageData: extracted.preprocessedImageData,
            extractionErrorDescription: extractionErrorDescription
        )
    }

    private static func errorFor(result: OCRImageResult) -> OCRError? {
        if result.allScores.isEmpty { return .noTextFound }
        let anyParseSucceeded = result.allScores.contains { $0.parseErrorDescription == nil }
        if anyParseSucceeded {
            return result.printout == nil ? .insufficientReadings : nil
        }
        return .unrecognizedFormat
    }

    private static func buildDebugEntry(_ result: OCRImageResult) -> OCRDebugSnapshot.Entry {
        OCRDebugSnapshot.Entry(
            photoIndex: result.photoIndex,
            rowBasedLines: result.rowBasedLines,
            rowBasedFormat: formatName(PrintoutParser.detect(rawLines: result.rowBasedLines)),
            columnBasedLines: result.columnBasedLines,
            columnBasedFormat: formatName(PrintoutParser.detect(rawLines: result.columnBasedLines)),
            chosenStrategy: result.winningScore?.reconstruction.rawValue ?? "none",
            parseError: result.winningScore?.parseErrorDescription ?? result.extractionErrorDescription,
            preprocessedImageData: result.preprocessedImageData,
            variantScores: result.allScores,
            revisionUsed: result.winningScore?.revisionUsed,
            winningVariant: result.winningScore?.variant.rawValue
        )
    }

    private static func formatName(_ detection: PrintoutFormatDetectionResult) -> String {
        switch detection {
        case .desktop: return "desktop"
        case .handheld: return "handheld"
        case .unknown: return "unknown"
        }
    }

    static func readingCount(_ result: PrintoutResult) -> Int {
        (result.rightEye?.readings.count ?? 0) + (result.leftEye?.readings.count ?? 0)
    }
}
