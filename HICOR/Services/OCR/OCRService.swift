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

/// Result of within-printout OCR consensus. Each cell's winning value is
/// chosen by majority vote across the photos of that printout; ties
/// break to the earliest photo carrying the tied value. `perImage`
/// holds the single merged PrintoutResult (represented as a one-element
/// array for continuity with the old batch API). `missingCells` names
/// catalog cells that no photo resolved. `disagreements` surfaces cells
/// where photos of the same sheet produced different values — per the
/// feedback_surface_automatic_exclusions memory, any automatic picking
/// between conflicting readings must be visible, not hidden.
struct OCRConsensusResult {
    struct Disagreement: Equatable {
        let cellLabel: String
        /// All distinct values seen for this cell, each paired with the
        /// photo indices that voted for it. The winner (first in the
        /// list) is the value chosen; later entries are the dissenters.
        let votes: [(value: String, photoIndices: [Int])]

        static func == (lhs: Disagreement, rhs: Disagreement) -> Bool {
            lhs.cellLabel == rhs.cellLabel &&
                lhs.votes.map(\.value) == rhs.votes.map(\.value) &&
                lhs.votes.map(\.photoIndices) == rhs.votes.map(\.photoIndices)
        }
    }

    let perImage: [PrintoutResult]
    let missingCells: [String]
    let disagreements: [Disagreement]
    let debugSnapshot: OCRDebugSnapshot
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

        OCRLog.logger.info("ParseScorer variant=\(extraction.variant.rawValue, privacy: .public) recon=\(reconstruction.rawValue, privacy: .public) rev=\(extraction.revisionUsed) reads=\(readings) readScore=\(readingScore, format: .fixed(precision: 3)) complete=\(completeness, format: .fixed(precision: 2)) markers=\(markerContinuity, format: .fixed(precision: 3)) conf=\(confidence, format: .fixed(precision: 3)) total=\(total, format: .fixed(precision: 3))")
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

    init(extractor: TextExtracting = ROIPipelineExtractor(fallback: MLKitTextExtractor())) {
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

    /// Runs consensus across a set of printouts, where each printout is
    /// represented by one or more photos of the SAME physical sheet.
    /// Consensus-borrowing happens only within a printout group, never
    /// across groups — photos of different sheets must not mix cell
    /// values. Returns one result per input group, in input order.
    func processPrintoutsWithConsensus(_ printouts: [[UIImage]]) async -> [OCRConsensusResult] {
        var out: [OCRConsensusResult] = []
        out.reserveCapacity(printouts.count)
        for group in printouts {
            out.append(await processImagesWithConsensus(group))
        }
        return out
    }

    /// Runs OCR across a set of photos assumed to be captures of the SAME
    /// physical printout. A cell missing from one photo is filled with
    /// the same cell's value from another photo that did resolve it. This
    /// is safe only within a single-sheet group — callers must not pass
    /// photos of different sheets here, use `processPrintoutsWithConsensus`
    /// for multi-sheet capture sets. `processImages` is retained for the
    /// per-photo strict mode used by existing test fixtures.
    func processImagesWithConsensus(_ images: [UIImage]) async -> OCRConsensusResult {
        var perPhoto: [(index: Int, partial: PartialCellExtraction)] = []
        var failureMessages: [String] = []

        for (index, image) in images.enumerated() {
            do {
                let partial = try await extractor.extractCellValues(from: image)
                perPhoto.append((index, partial))
                OCRLog.logger.info("Consensus photo=\(index, privacy: .public) resolved=\(partial.values.count, privacy: .public) missing=\(partial.missing.count, privacy: .public)")
            } catch {
                let message = "photo \(index) extraction failed: \(String(describing: error))"
                OCRLog.logger.error("Consensus \(message, privacy: .public)")
                failureMessages.append(message)
            }
        }

        // No photo even gave us anchors — nothing to merge.
        guard !perPhoto.isEmpty else {
            let snapshot = OCRDebugSnapshot(
                entries: [],
                overallError: failureMessages.first ?? "no photos produced extractions"
            )
            return OCRConsensusResult(
                perImage: [],
                missingCells: ["no readable photo — recapture required"],
                disagreements: [],
                debugSnapshot: snapshot
            )
        }

        // The full CellIdentity catalog is the same across any photo that
        // made it through anchor detection — driven by the layout, not
        // the image. Use the first photo's cells as the catalog probe.
        let catalog: [CellIdentity] = perPhoto[0].partial.cells.map(CellIdentity.init)

        // Collect every vote for every cell across photos. A "vote" is
        // one photo's resolved value for that cell; nil resolutions don't
        // vote. Majority wins below — ties break to the value whose
        // earliest-voting photo came first in the capture order.
        var votesByIdentity: [CellIdentity: [(value: String, photoIndex: Int)]] = [:]
        for (photoIndex, partial) in perPhoto {
            for (cell, value) in partial.values {
                let id = CellIdentity(cell)
                votesByIdentity[id, default: []].append((value, photoIndex))
            }
        }

        // Resolve each cell by majority vote, and track disagreements
        // (cells where photos of the same sheet produced different
        // values) so the UI can surface them.
        var valuesByIdentity: [CellIdentity: String] = [:]
        var disagreements: [OCRConsensusResult.Disagreement] = []
        for (id, votes) in votesByIdentity {
            let distinct = Dictionary(grouping: votes, by: \.value)
            let maxCount = distinct.values.map(\.count).max() ?? 0
            // Value groups tied for the most votes. Among those, pick the
            // group whose earliest-voting photo came first — a conservative,
            // deterministic tie-break.
            let topGroups = distinct.filter { $0.value.count == maxCount }
            let winner = topGroups.min { lhs, rhs in
                let lMin = lhs.value.map(\.photoIndex).min() ?? Int.max
                let rMin = rhs.value.map(\.photoIndex).min() ?? Int.max
                return lMin < rMin
            }
            guard let winner else { continue }
            valuesByIdentity[id] = winner.key

            if distinct.count > 1 {
                // Record the disagreement so it gets logged and can be
                // surfaced to the operator. Winner first, dissenters after.
                var voteList: [(value: String, photoIndices: [Int])] = []
                let winnerIndices = distinct[winner.key]!.map(\.photoIndex).sorted()
                voteList.append((winner.key, winnerIndices))
                for (value, group) in distinct where value != winner.key {
                    voteList.append((value, group.map(\.photoIndex).sorted()))
                }
                disagreements.append(OCRConsensusResult.Disagreement(
                    cellLabel: id.label,
                    votes: voteList
                ))
                let summary = voteList.map { "\($0.value)×\($0.photoIndices.count)" }.joined(separator: ", ")
                OCRLog.logger.info("Consensus DISAGREEMENT cell=\(id.label, privacy: .public) votes=\(summary, privacy: .public) chose=\(winner.key, privacy: .public)")
            }
        }

        // Catalog cells nobody resolved — recapture required.
        let stillMissing: [String] = catalog.compactMap { id in
            valuesByIdentity[id] == nil ? id.label : nil
        }

        guard stillMissing.isEmpty else {
            return OCRConsensusResult(
                perImage: [],
                missingCells: stillMissing,
                disagreements: disagreements,
                debugSnapshot: OCRDebugSnapshot(
                    entries: [],
                    overallError: "incompleteCells across all photos: \(stillMissing.joined(separator: ", "))"
                )
            )
        }

        // One merged PrintoutResult per printout group. Tag sourcePhotoIndex
        // with the first photo's index so audit trails refer to the capture
        // that triggered the analysis.
        var rowBased = assembleRowLinesByIdentity(valuesByIdentity: valuesByIdentity)
        if let consensusPD = consensusPD(perPhoto: perPhoto) {
            rowBased.append(ROIPipelineExtractor.formatPDLine(consensusPD))
        }
        let anchorPhotoIndex = perPhoto.first!.index
        guard let parsed = try? PrintoutParser.parse(lines: rowBased, photoIndex: anchorPhotoIndex) else {
            return OCRConsensusResult(
                perImage: [],
                missingCells: [],
                disagreements: disagreements,
                debugSnapshot: OCRDebugSnapshot(
                    entries: [],
                    overallError: "PrintoutParser failed on merged rowBased"
                )
            )
        }

        let snapshotEntry = OCRDebugSnapshot.Entry(
            photoIndex: anchorPhotoIndex,
            rowBasedLines: rowBased,
            rowBasedFormat: "desktop",
            columnBasedLines: rowBased,
            columnBasedFormat: "desktop",
            chosenStrategy: "consensus",
            parseError: nil,
            preprocessedImageData: nil,
            variantScores: [],
            revisionUsed: 0,
            winningVariant: nil
        )
        return OCRConsensusResult(
            perImage: [parsed],
            missingCells: [],
            disagreements: disagreements,
            debugSnapshot: OCRDebugSnapshot(entries: [snapshotEntry], overallError: "")
        )
    }

    /// PD consensus across photos of the same printout. Mirrors the cell
    /// vote rule (majority value wins; tie-break to the value whose earliest
    /// photo came first in capture order) so behavior stays predictable
    /// across the readings grid and the PD field. Nil PDs don't vote.
    /// PD lives outside the cell map per Section 9 of the procedure doc:
    /// per-printout aggregation happens here, cross-printout averaging
    /// happens in PDAggregator.
    private func consensusPD(perPhoto: [(index: Int, partial: PartialCellExtraction)]) -> Double? {
        let votes: [(value: Double, photoIndex: Int)] = perPhoto.compactMap { item in
            guard let pd = item.partial.pd else { return nil }
            return (pd, item.index)
        }
        guard !votes.isEmpty else { return nil }
        let groups = Dictionary(grouping: votes, by: \.value)
        let maxCount = groups.values.map(\.count).max() ?? 0
        let topGroups = groups.filter { $0.value.count == maxCount }
        let winner = topGroups.min { lhs, rhs in
            let lMin = lhs.value.map(\.photoIndex).min() ?? Int.max
            let rMin = rhs.value.map(\.photoIndex).min() ?? Int.max
            return lMin < rMin
        }
        return winner?.key
    }

    /// Identity key for cells that ignores the per-photo rect. Cells of
    /// the same (eye, column, row) across different photos are the same
    /// physical measurement, so consensus treats them as interchangeable.
    private struct CellIdentity: Hashable {
        let eye: CellROI.Eye
        let column: CellROI.Column
        let row: CellROI.Row

        init(_ cell: CellROI) {
            self.eye = cell.eye
            self.column = cell.column
            self.row = cell.row
        }

        init(eye: CellROI.Eye, column: CellROI.Column, row: CellROI.Row) {
            self.eye = eye
            self.column = column
            self.row = row
        }

        var label: String { "\(eye.rawValue) \(column.rawValue) \(row.rawValue)" }
    }

    /// Assemble rowBased lines directly from the identity-keyed value map.
    /// Output matches ROIPipelineExtractor's own assembly format so the
    /// existing PrintoutParser handles it unchanged.
    private func assembleRowLinesByIdentity(valuesByIdentity: [CellIdentity: String]) -> [String] {
        var lines: [String] = []
        for eye in [CellROI.Eye.right, .left] {
            lines.append(eye == .right ? "[R]" : "[L]")
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                let sph = valuesByIdentity[CellIdentity(eye: eye, column: .sph, row: row)] ?? ""
                let cyl = valuesByIdentity[CellIdentity(eye: eye, column: .cyl, row: row)] ?? ""
                let ax  = valuesByIdentity[CellIdentity(eye: eye, column: .ax,  row: row)] ?? ""
                let prefix = row == .avg ? "AVG " : ""
                lines.append("\(prefix)\(sph) \(cyl) \(ax)")
            }
        }
        return lines
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
            OCRLog.logger.error("OCR extractor threw: \(String(describing: error), privacy: .public)")
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

        OCRLog.logger.info("OCR strategy=\(winningScore?.reconstruction.rawValue ?? "none", privacy: .public) reads=\(winningScore?.validReadingCount ?? 0) score=\(winningScore?.totalScore ?? 0, format: .fixed(precision: 3))")

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
