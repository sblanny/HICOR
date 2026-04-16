import Foundation
import UIKit
import Vision

struct TextBox: Equatable {
    let midX: CGFloat
    let midY: CGFloat
    let minX: CGFloat
    let text: String
}

struct ExtractedText: Equatable {
    let rowBased: [String]
    let columnBased: [String]

    static let empty = ExtractedText(rowBased: [], columnBased: [])
}

protocol TextExtracting {
    func extractText(from image: UIImage) async throws -> ExtractedText
}

enum VisionTextExtractorError: Error {
    case missingCGImage
    case visionFailed(Error)
}

final class VisionTextExtractor: TextExtracting {

    static let defaultRowTolerance: CGFloat = 0.02
    static let defaultColumnGapThreshold: CGFloat = 0.08

    func extractText(from image: UIImage) async throws -> ExtractedText {
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
                let boxes = Self.toTextBoxes(observations)
                continuation.resume(returning: ExtractedText(
                    rowBased: Self.reconstructRows(from: boxes),
                    columnBased: Self.reconstructColumnarLines(from: boxes)
                ))
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

    private static func toTextBoxes(_ observations: [VNRecognizedTextObservation]) -> [TextBox] {
        observations.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return TextBox(
                midX: obs.boundingBox.midX,
                midY: obs.boundingBox.midY,
                minX: obs.boundingBox.minX,
                text: text
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
