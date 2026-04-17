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

        struct Entry { let primary: CGFloat; let secondary: CGFloat; let text: String }
        var entries: [Entry] = []
        for block in result.blocks {
            for line in block.lines {
                if isImagePortrait {
                    // Document rotated 90° in a portrait image:
                    //   image X (left → right) = document Y (top → bottom)
                    //   image Y (top → bottom) = document X (left → right)
                    entries.append(Entry(
                        primary: line.frame.minX,
                        secondary: line.frame.minY,
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

        // Tolerance is in raw image pixels, so it scales naturally with
        // capture resolution. ~60 px on a 3024×4032 image is roughly one
        // line-height; lines that share a row collapse together and tiebreak
        // on the secondary axis (left-to-right within the row).
        let rowTolerance: CGFloat = 60.0
        entries.sort { a, b in
            if abs(a.primary - b.primary) < rowTolerance {
                return a.secondary < b.secondary
            }
            return a.primary < b.primary
        }

        // Group entries that share a row (within rowTolerance on the primary
        // axis) into one joined string. Parsers expect one full printed row
        // per element — e.g. "- 4.25  - 1.25  18" as a single line — not
        // four atomic ML Kit lines. Anchor on the row's first entry so
        // rows whose chain of neighbours drifts past the tolerance still
        // split cleanly.
        var rowBased: [String] = []
        var currentTexts: [String] = []
        var anchor: CGFloat?
        for entry in entries {
            if let a = anchor, abs(entry.primary - a) >= rowTolerance {
                rowBased.append(currentTexts.joined(separator: "  "))
                currentTexts = []
                anchor = nil
            }
            if anchor == nil { anchor = entry.primary }
            currentTexts.append(entry.text)
        }
        if !currentTexts.isEmpty {
            rowBased.append(currentTexts.joined(separator: "  "))
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
}
