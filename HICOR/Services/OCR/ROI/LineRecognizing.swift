import UIKit
import MLKitTextRecognition
import MLKitVision

/// One line of text recognized by an OCR engine. Frames are in the source
/// image's pixel coordinate space (origin top-left).
struct OCRLine: Equatable {
    let text: String
    let frame: CGRect
}

/// Abstraction over ML Kit's TextRecognizer that lets tests stub the OCR
/// engine without booting the real ML Kit runtime.
protocol LineRecognizing {
    func recognize(_ image: UIImage) async throws -> [OCRLine]
}

final class MLKitLineRecognizer: LineRecognizing {

    enum RecognizerError: Error {
        case noResult
        case failed(Error)
    }

    private let recognizer: TextRecognizer

    init(recognizer: TextRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())) {
        self.recognizer = recognizer
    }

    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        let text: Text = try await withCheckedThrowingContinuation { cont in
            recognizer.process(visionImage) { text, error in
                if let error { cont.resume(throwing: RecognizerError.failed(error)); return }
                guard let text else { cont.resume(throwing: RecognizerError.noResult); return }
                cont.resume(returning: text)
            }
        }
        // Emit element-level granularity so AnchorDetector can see tokens
        // like "<R>", "SPH", "CYL", "AX" that ML Kit otherwise fuses into a
        // single header line. CellOCR still works against elements because
        // cell crops typically contain a single token (e.g. "-0.50") that
        // matches the full decimal regex on its own.
        return text.blocks.flatMap { block in
            block.lines.flatMap { line in
                line.elements.map { OCRLine(text: $0.text, frame: $0.frame) }
            }
        }
    }
}
