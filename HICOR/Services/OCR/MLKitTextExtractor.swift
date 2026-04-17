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
        print("Blocks: \(result.blocks.count)")
        for (bi, block) in result.blocks.enumerated() {
            print("Block \(bi): frame=\(block.frame) lines=\(block.lines.count)")
            for (li, line) in block.lines.enumerated() {
                print("  Line \(bi).\(li): frame=\(line.frame) text='\(line.text)'")
            }
        }
        print("=== End ML Kit Raw ===")

        // Temporary strategy: sort BLOCKS by top-Y, then emit each block's
        // lines in their natural within-block order. ML Kit typically gets
        // intra-block order right; the prior top-level Y sort across all
        // lines was producing scrambled output on the handheld printout.
        // We'll revisit after the device logs reveal how block/line frames
        // actually lay out on a real desktop printout.
        let sortedBlocks = result.blocks.sorted {
            $0.frame.minY < $1.frame.minY
        }

        var rowBased: [String] = []
        for block in sortedBlocks {
            for line in block.lines {
                rowBased.append(line.text)
            }
        }

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
