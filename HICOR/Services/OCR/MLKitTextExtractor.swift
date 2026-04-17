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

        let boxes = Self.toTextBoxes(result, imageSize: image.size)
        let thresholds = VisionTextExtractor.computeAdaptiveThresholds(from: boxes)
        return ExtractedText(
            rowBased: VisionTextExtractor.reconstructRows(
                from: boxes,
                rowTolerance: thresholds.rowTolerance
            ),
            columnBased: VisionTextExtractor.reconstructColumnarLines(
                from: boxes,
                columnGapThreshold: thresholds.columnGapThreshold,
                rowTolerance: thresholds.rowTolerance
            ),
            preprocessedImageData: image.jpegData(compressionQuality: 0.85),
            boxes: boxes,
            revisionUsed: 0,
            variant: variant
        )
    }

    /// Maps ML Kit's `Text` to the Vision-style `TextBox` array the existing
    /// reconstruction statics expect. ML Kit returns line frames in pixel
    /// coordinates with top-left origin; `TextBox` is normalized 0–1 with
    /// bottom-left origin. The Y-flip is essential — without it row sorting
    /// reverses and `[R]` lands below `[L]`.
    ///
    /// ML Kit v2's Swift API does not expose per-line confidence, so all
    /// boxes get `confidence: 1.0`. This makes `ParseScorer.wConfidence`
    /// uniform across the row/column comparison; the other three weights
    /// drive selection.
    private static func toTextBoxes(_ text: Text, imageSize: CGSize) -> [TextBox] {
        guard imageSize.width > 0, imageSize.height > 0 else { return [] }
        return text.blocks.flatMap { block in
            block.lines.map { line -> TextBox in
                let frame = line.frame
                return TextBox(
                    midX: frame.midX / imageSize.width,
                    midY: 1.0 - frame.midY / imageSize.height,
                    minX: frame.minX / imageSize.width,
                    height: frame.height / imageSize.height,
                    text: line.text,
                    confidence: 1.0
                )
            }
        }
    }
}
