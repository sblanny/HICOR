import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import Vision

enum PreprocessingVariant: String, Codable, CaseIterable, Equatable {
    case standard
    case thermalBinary
    case raw
}

struct TextBox: Equatable {
    let midX: CGFloat
    let midY: CGFloat
    let minX: CGFloat
    let height: CGFloat
    let text: String
    let confidence: Float

    init(midX: CGFloat, midY: CGFloat, minX: CGFloat, height: CGFloat = 0.0, text: String, confidence: Float = 1.0) {
        self.midX = midX
        self.midY = midY
        self.minX = minX
        self.height = height
        self.text = text
        self.confidence = confidence
    }
}

struct ExtractedText: Equatable {
    let rowBased: [String]
    let columnBased: [String]
    let preprocessedImageData: Data?
    let boxes: [TextBox]
    let revisionUsed: Int
    let variant: PreprocessingVariant

    init(
        rowBased: [String],
        columnBased: [String],
        preprocessedImageData: Data? = nil,
        boxes: [TextBox] = [],
        revisionUsed: Int = VNRecognizeTextRequestRevision3,
        variant: PreprocessingVariant = .standard
    ) {
        self.rowBased = rowBased
        self.columnBased = columnBased
        self.preprocessedImageData = preprocessedImageData
        self.boxes = boxes
        self.revisionUsed = revisionUsed
        self.variant = variant
    }

    static let empty = ExtractedText(rowBased: [], columnBased: [])
}

protocol TextExtracting {
    func extractText(from image: UIImage) async throws -> ExtractedText
    func extractText(from image: UIImage, variant: PreprocessingVariant, revision: Int) async throws -> ExtractedText
}

extension TextExtracting {
    func extractText(from image: UIImage, variant: PreprocessingVariant, revision: Int) async throws -> ExtractedText {
        try await extractText(from: image)
    }
}

enum VisionTextExtractorError: Error {
    case missingCGImage
    case visionFailed(Error)
}

final class VisionTextExtractor: TextExtracting {

    static let defaultRowTolerance: CGFloat = 0.02
    static let defaultColumnGapThreshold: CGFloat = 0.08

    struct AdaptiveThresholds: Equatable {
        let rowTolerance: CGFloat
        let columnGapThreshold: CGFloat
    }

    static func computeAdaptiveThresholds(from boxes: [TextBox]) -> AdaptiveThresholds {
        guard boxes.count >= 4 else {
            return AdaptiveThresholds(
                rowTolerance: defaultRowTolerance,
                columnGapThreshold: defaultColumnGapThreshold
            )
        }

        let heights = boxes.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        let rowTol = max(medianHeight * 0.6, 0.008)

        var rowGroups: [[TextBox]] = []
        for box in boxes.sorted(by: { $0.midY > $1.midY }) {
            if let idx = rowGroups.firstIndex(where: {
                abs(($0.first?.midY ?? 0) - box.midY) < rowTol
            }) {
                rowGroups[idx].append(box)
            } else {
                rowGroups.append([box])
            }
        }

        var gaps: [CGFloat] = []
        for var row in rowGroups {
            row.sort { $0.minX < $1.minX }
            if row.count >= 2 {
                for i in 1..<row.count {
                    let gap = row[i].minX - row[i - 1].minX
                    if gap > 0 { gaps.append(gap) }
                }
            }
        }
        guard gaps.count >= 3 else {
            return AdaptiveThresholds(rowTolerance: rowTol, columnGapThreshold: defaultColumnGapThreshold)
        }
        gaps.sort()
        let p75Index = min(Int(Double(gaps.count) * 0.75), gaps.count - 1)
        let colGap = max(gaps[p75Index], 0.03)

        return AdaptiveThresholds(rowTolerance: rowTol, columnGapThreshold: colGap)
    }

    private static let customWords: [String] = [
        "SPH", "CYL", "AX", "AQ", "REF", "PD", "VD", "AVG",
        "[R]", "[L]", "<R>", "<L>",
        "Name", "No"
    ]

    private let ciContext = CIContext(options: nil)

    func extractText(from image: UIImage) async throws -> ExtractedText {
        try await extractText(from: image, variant: .standard, revision: Self.latestRevision())
    }

    func extractText(
        from image: UIImage,
        variant: PreprocessingVariant,
        revision: Int
    ) async throws -> ExtractedText {
        guard let (rawCG, orientation) = Self.normalizedCGImage(from: image) else {
            throw VisionTextExtractorError.missingCGImage
        }
        let preprocessedCG: CGImage = {
            switch variant {
            case .standard: return preprocessStandard(cgImage: rawCG) ?? rawCG
            case .thermalBinary: return preprocessThermalBinary(cgImage: rawCG) ?? rawCG
            case .raw: return preprocessRaw(cgImage: rawCG) ?? rawCG
            }
        }()
        let preprocessedJPEG = uprightJPEG(cgImage: preprocessedCG, orientation: orientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: VisionTextExtractorError.visionFailed(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let boxes = Self.toTextBoxes(observations)
                let thresholds = Self.computeAdaptiveThresholds(from: boxes)
                continuation.resume(returning: ExtractedText(
                    rowBased: Self.reconstructRows(from: boxes, rowTolerance: thresholds.rowTolerance),
                    columnBased: Self.reconstructColumnarLines(
                        from: boxes,
                        columnGapThreshold: thresholds.columnGapThreshold,
                        rowTolerance: thresholds.rowTolerance
                    ),
                    preprocessedImageData: preprocessedJPEG,
                    boxes: boxes,
                    revisionUsed: revision,
                    variant: variant
                ))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.customWords = Self.customWords
            request.minimumTextHeight = 0.01
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = false
                request.revision = revision
            }

            let handler = VNImageRequestHandler(cgImage: preprocessedCG, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: VisionTextExtractorError.visionFailed(error))
            }
        }
    }

    static func latestRevision() -> Int {
        let supported = VNRecognizeTextRequest.supportedRevisions.sorted(by: >)
        return supported.first ?? VNRecognizeTextRequestRevision3
    }

    static func revisionsToTry() -> [Int] {
        let supported = VNRecognizeTextRequest.supportedRevisions.sorted(by: >)
        if supported.isEmpty { return [VNRecognizeTextRequestRevision3] }
        return Array(supported.prefix(2))
    }

    private static func normalizedCGImage(from image: UIImage) -> (CGImage, CGImagePropertyOrientation)? {
        guard let cg = image.cgImage else { return nil }
        let orientation: CGImagePropertyOrientation
        switch image.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        return (cg, orientation)
    }

    private func preprocessStandard(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)

        var processed = ciImage.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))

        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(processed, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            filter.setValue(1.8, forKey: kCIInputContrastKey)
            filter.setValue(0.05, forKey: kCIInputBrightnessKey)
            processed = filter.outputImage ?? processed
        }

        if let sharp = CIFilter(name: "CIUnsharpMask") {
            sharp.setValue(processed, forKey: kCIInputImageKey)
            sharp.setValue(0.7, forKey: kCIInputIntensityKey)
            sharp.setValue(2.5, forKey: "inputRadius")
            processed = sharp.outputImage ?? processed
        }

        return ciContext.createCGImage(processed, from: processed.extent)
    }

    private func preprocessRaw(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    private func preprocessThermalBinary(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        var processed = ciImage.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(processed, forKey: kCIInputImageKey)
            filter.setValue(0.0, forKey: kCIInputSaturationKey)
            filter.setValue(2.5, forKey: kCIInputContrastKey)
            filter.setValue(0.15, forKey: kCIInputBrightnessKey)
            processed = filter.outputImage ?? processed
        }
        if let threshold = CIFilter(name: "CIColorThreshold") {
            threshold.setValue(processed, forKey: kCIInputImageKey)
            threshold.setValue(0.55, forKey: "inputThreshold")
            processed = threshold.outputImage ?? processed
        }
        return ciContext.createCGImage(processed, from: processed.extent)
    }

    private func uprightJPEG(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> Data? {
        let upright = CIImage(cgImage: cgImage).oriented(orientation)
        guard let uprightCG = ciContext.createCGImage(upright, from: upright.extent) else {
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        }
        return UIImage(cgImage: uprightCG).jpegData(compressionQuality: 0.7)
    }

    private static func toTextBoxes(_ observations: [VNRecognizedTextObservation]) -> [TextBox] {
        observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return TextBox(
                midX: obs.boundingBox.midX,
                midY: obs.boundingBox.midY,
                minX: obs.boundingBox.minX,
                height: obs.boundingBox.height,
                text: candidate.string,
                confidence: candidate.confidence
            )
        }
    }

    static func reconstructRows(
        from boxes: [TextBox],
        rowTolerance: CGFloat = defaultRowTolerance
    ) -> [String] {
        var rows: [[TextBox]] = []
        for box in boxes {
            if let rowIndex = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.midY - box.midY) < rowTolerance
            }) {
                rows[rowIndex].append(box)
            } else {
                rows.append([box])
            }
        }

        rows.sort { lhs, rhs in
            guard let l = lhs.first, let r = rhs.first else { return false }
            return l.midY > r.midY
        }

        return rows.map { row -> String in
            row.sorted { $0.minX < $1.minX }
               .map(\.text)
               .joined(separator: "  ")
        }
    }

    static func reconstructColumnarLines(
        from boxes: [TextBox],
        columnGapThreshold: CGFloat = defaultColumnGapThreshold,
        rowTolerance: CGFloat = defaultRowTolerance
    ) -> [String] {
        let rMarker = boxes.first { $0.text.contains("[R]") || $0.text.contains("<R>") }
        let lMarker = boxes.first { $0.text.contains("[L]") || $0.text.contains("<L>") }

        guard let r = rMarker, let l = lMarker, r.midY > l.midY else {
            return reconstructColumnsInSection(boxes, columnGapThreshold: columnGapThreshold)
        }

        let starsByYDesc = boxes.filter { $0.text.hasPrefix("*") }.sorted { $0.midY > $1.midY }
        let firstStar = starsByYDesc.first { $0.midY < r.midY && $0.midY > l.midY }
        let secondStar = starsByYDesc.first { $0.midY < l.midY }

        var output: [String] = []

        let preBoxes = boxes.filter { $0.midY > r.midY }
        if !preBoxes.isEmpty {
            output.append(contentsOf: reconstructColumnsInSection(preBoxes, columnGapThreshold: columnGapThreshold))
        }

        output.append("[R]")
        let rightLowerBound = firstStar?.midY ?? l.midY
        let rightDataBoxes = boxes.filter { box in
            box != r && box.midY < r.midY && box.midY > rightLowerBound
        }
        output.append(contentsOf: reconstructColumnsInSection(rightDataBoxes, columnGapThreshold: columnGapThreshold))
        if let star = firstStar {
            output.append(rowAroundY(in: boxes, y: star.midY, tolerance: rowTolerance))
        }

        output.append("[L]")
        let leftLowerBound = secondStar?.midY ?? -1.0
        let leftDataBoxes = boxes.filter { box in
            box != l && box.midY < l.midY && box.midY > leftLowerBound
        }
        output.append(contentsOf: reconstructColumnsInSection(leftDataBoxes, columnGapThreshold: columnGapThreshold))
        if let star = secondStar {
            output.append(rowAroundY(in: boxes, y: star.midY, tolerance: rowTolerance))
        }

        return output
    }

    private static func rowAroundY(in boxes: [TextBox], y: CGFloat, tolerance: CGFloat) -> String {
        boxes.filter { abs($0.midY - y) < tolerance }
             .sorted { $0.minX < $1.minX }
             .map(\.text)
             .joined(separator: "  ")
    }

    static func reconstructColumnsInSection(
        _ boxes: [TextBox],
        columnGapThreshold: CGFloat = defaultColumnGapThreshold
    ) -> [String] {
        guard !boxes.isEmpty else { return [] }

        let sortedX = boxes.map(\.midX).sorted()
        var columnCenters: [CGFloat] = []
        var current: [CGFloat] = []
        for x in sortedX {
            if let last = current.last, x - last >= columnGapThreshold {
                columnCenters.append(current.reduce(0, +) / CGFloat(current.count))
                current = [x]
            } else {
                current.append(x)
            }
        }
        if !current.isEmpty {
            columnCenters.append(current.reduce(0, +) / CGFloat(current.count))
        }

        guard !columnCenters.isEmpty else { return [] }

        var columns: [[TextBox]] = Array(repeating: [], count: columnCenters.count)
        for box in boxes {
            let nearest = columnCenters.enumerated()
                .min(by: { abs($0.element - box.midX) < abs($1.element - box.midX) })!
                .offset
            columns[nearest].append(box)
        }

        for i in columns.indices {
            columns[i].sort { $0.midY > $1.midY }
        }

        let maxRows = columns.map(\.count).max() ?? 0
        var rows: [String] = []
        for rowIdx in 0..<maxRows {
            let rowTexts = columns.compactMap { col -> String? in
                guard rowIdx < col.count else { return nil }
                return col[rowIdx].text
            }
            rows.append(rowTexts.joined(separator: "  "))
        }
        return rows
    }
}
