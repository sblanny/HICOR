import Foundation
import UIKit
import MLKitTextRecognition
import MLKitVision

enum MLKitTextExtractorError: Error {
    case noResult
    case recognitionFailed(Error)
}

/// Default text extractor as of 2026-04-17. ML Kit Text Recognition v2 produces
/// a Block → Line → Element hierarchy with atomic decimals and reliable row
/// segmentation, replacing Apple Vision which fragments numbers like "+1.25"
/// into separate observations the parser cannot recover.
///
/// `variant` and `revision` are accepted for `TextExtracting` protocol parity
/// but are no-ops — ML Kit handles preprocessing internally and has no
/// revision concept. `revisionUsed: 0` in the returned ExtractedText is the
/// breadcrumb that ML Kit (not Vision) ran.
final class MLKitTextExtractor: TextExtracting {

    private struct Entry {
        let primary: CGFloat
        let secondary: CGFloat
        let text: String
    }

    private let recognizer: TextRecognizer

    init() {
        let options = TextRecognizerOptions()
        self.recognizer = TextRecognizer.textRecognizer(options: options)
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        try await extractText(from: image, variant: .raw, revision: 0)
    }

    func extractText(
        from image: UIImage,
        variant: PreprocessingVariant,
        revision: Int
    ) async throws -> ExtractedText {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation

        let result: Text = try await withCheckedThrowingContinuation { continuation in
            recognizer.process(visionImage) { text, error in
                if let error {
                    continuation.resume(throwing: MLKitTextExtractorError.recognitionFailed(error))
                    return
                }
                guard let text else {
                    continuation.resume(throwing: MLKitTextExtractorError.noResult)
                    return
                }
                continuation.resume(returning: text)
            }
        }

        // Verbose diagnostic logging — temporary, will remove once
        // reconstruction is stable.
        print("=== ML Kit Raw Structure ===")
        print("Image size: \(image.size)")
        print("Image orientation: \(image.imageOrientation.rawValue)")
        print("Blocks: \(result.blocks.count)")
        for (bi, block) in result.blocks.enumerated() {
            print("Block \(bi): frame=\(block.frame) lines=\(block.lines.count)")
            for (li, line) in block.lines.enumerated() {
                print("  Line \(bi).\(li): frame=\(line.frame) text='\(line.text)'")
            }
        }
        print("=== End ML Kit Raw ===")

        // Detect document orientation relative to the image.
        // Real-device captures of the GRK-6000 desktop printout come in as a
        // 3024×4032 portrait image even though the printout itself was
        // photographed landscape — so the document's top edge runs down the
        // image's LEFT side. Sorting by frame.minY in that case reads the
        // document right-to-left. When the image is landscape (width > height)
        // the document is correctly oriented and the natural Y-then-X sort
        // applies. This is a heuristic for typical capture orientation; once
        // we have more device data we can replace it with anchor-text-based
        // detection (e.g. locating "AVG" or "GAK-6000" markers).
        let isImagePortrait = image.size.height > image.size.width

        var entries: [Entry] = []
        for block in result.blocks {
            for line in block.lines {
                if isImagePortrait {
                    // Document rotated 90° clockwise in a portrait .right-
                    // orientation image (iPhone held portrait, subject shot
                    // landscape): the document's top edge runs down the
                    // image's LEFT side, so
                    //   image X ascending   = document Y top → bottom
                    //   image Y DESCENDING  = document X left → right
                    // We negate imgY so ascending sort of secondary tracks
                    // document-left-to-right within a row.
                    entries.append(Entry(
                        primary: line.frame.minX,
                        secondary: -line.frame.minY,
                        text: line.text
                    ))
                } else {
                    entries.append(Entry(
                        primary: line.frame.minY,
                        secondary: line.frame.minX,
                        text: line.text
                    ))
                }
            }
        }

        // Tilt correction. Real-device captures of the GRK-6000 printout are
        // rarely perfectly square to the camera — a few degrees of tilt drifts
        // each document-row diagonally in image space at a slope that can push
        // intra-row primary spread beyond the anchor tolerance, shattering a
        // single reading into two or three groups. The column header row
        // (SPH / CYL / AX) is guaranteed to be collinear on one document-row,
        // so fitting a line through those tokens gives the tilt angle exactly.
        // Subtracting that slope from each entry's primary collapses rows
        // back to tight clusters (~10 px spread) well inside the 60 px
        // tolerance.
        let tilt = Self.estimateTilt(entries: entries)
        print("=== Tilt Correction === slope=\(tilt)")
        if tilt != 0 {
            entries = entries.map {
                Entry(
                    primary: $0.primary - tilt * $0.secondary,
                    secondary: $0.secondary,
                    text: $0.text
                )
            }
        }

        // Tolerance is in raw image pixels, so it scales naturally with
        // capture resolution. ~60 px on a 3024×4032 image is roughly one
        // line-height. We sort primary-only (strict weak ordering) then
        // form groups via an anchor walk; mixing tolerance tiebreaks into
        // the comparator is non-transitive and gives Swift's sort undefined
        // output — that bug produced scrambled row groups on device.
        let rowTolerance: CGFloat = 60.0
        entries.sort { $0.primary < $1.primary }

        var rowGroups: [[Entry]] = []
        var currentGroup: [Entry] = []
        var anchor: CGFloat?
        for entry in entries {
            if let a = anchor, entry.primary - a >= rowTolerance {
                rowGroups.append(currentGroup)
                currentGroup = []
                anchor = nil
            }
            if anchor == nil { anchor = entry.primary }
            currentGroup.append(entry)
        }
        if !currentGroup.isEmpty { rowGroups.append(currentGroup) }

        let rowBased: [String] = rowGroups.map { group in
            group.sorted { $0.secondary < $1.secondary }
                .map(\.text)
                .joined(separator: "  ")
        }

        print("=== Row Groups After Reconstruction ===")
        for (i, row) in rowBased.enumerated() {
            print("Row \(i): '\(row)'")
        }
        print("=== End Row Groups ===")

        // Temporary: column-based mirrors row-based until row reconstruction
        // is proven. Vision's columnar reconstruction is bypassed entirely
        // in this diagnostic pass.
        let columnBased = rowBased

        let boxes = result.blocks.flatMap { block in
            block.lines.map { line in
                TextBox(
                    midX: line.frame.midX / image.size.width,
                    midY: line.frame.midY / image.size.height,
                    minX: line.frame.minX / image.size.width,
                    height: line.frame.height / image.size.height,
                    text: line.text,
                    confidence: 1.0
                )
            }
        }

        return ExtractedText(
            rowBased: rowBased,
            columnBased: columnBased,
            preprocessedImageData: image.jpegData(compressionQuality: 0.85),
            boxes: boxes,
            revisionUsed: 0,
            variant: variant
        )
    }

    /// Fit a line through the SPH/CYL/AX column-header row to measure document
    /// tilt in the (primary, secondary) coordinate space. Returns the slope
    /// d(primary)/d(secondary); applying `p - slope * s` to every entry's
    /// primary axis removes the tilt. Returns 0 when we can't find at least
    /// two collinear headers (conservative — no correction rather than wrong
    /// correction).
    private static func estimateTilt(entries: [Entry]) -> CGFloat {
        let headerTexts: Set<String> = ["SPH", "CYL", "AX"]
        let headers = entries.filter { headerTexts.contains($0.text.uppercased()) }
        guard headers.count >= 2 else { return 0 }

        // Cluster headers using the same 60 px intra-row tolerance the row
        // grouper uses. A looser threshold can sweep in stray "CYL (-)"-style
        // document-wide notes that share a header label but live on their own
        // row, which biases the regression and inverts the slope. Then prefer
        // a cluster with all three headers (SPH + CYL + AX) before falling
        // back to any two-header cluster — three collinear points give a
        // dramatically more stable fit.
        let headerTolerance: CGFloat = 60
        let sorted = headers.sorted { $0.primary < $1.primary }
        var clusters: [[Entry]] = [[sorted[0]]]
        for entry in sorted.dropFirst() {
            let lastEntry = clusters[clusters.count - 1].last!
            if entry.primary - lastEntry.primary < headerTolerance {
                clusters[clusters.count - 1].append(entry)
            } else {
                clusters.append([entry])
            }
        }
        let ordered = clusters.sorted { $0.count > $1.count }
        for cluster in ordered where cluster.count >= 2 {
            let xs = cluster.map(\.secondary)
            let ys = cluster.map(\.primary)
            let n = CGFloat(xs.count)
            let sumX = xs.reduce(0, +)
            let sumY = ys.reduce(0, +)
            let sumXY = zip(xs, ys).map(*).reduce(0, +)
            let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            if abs(denom) > 1e-6 {
                return (n * sumXY - sumX * sumY) / denom
            }
        }
        return 0
    }
}
