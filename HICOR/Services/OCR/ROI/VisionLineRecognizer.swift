import UIKit
import Vision

/// Apple Vision alternative to MLKitLineRecognizer. Used by CellOCR as a
/// second-opinion engine on unresolved cells — Vision and ML Kit have
/// complementary failure modes on dim thermal values, so chaining catches
/// cells one engine alone would miss.
final class VisionLineRecognizer: LineRecognizing {

    enum RecognizerError: Error {
        case missingCGImage
        case failed(Error)
    }

    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        guard let cg = image.cgImage else { throw RecognizerError.missingCGImage }
        let orientation = cgOrientation(from: image.imageOrientation)
        let size = CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))

        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: RecognizerError.failed(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [OCRLine] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let bb = obs.boundingBox
                    let frame = CGRect(
                        x: bb.minX * size.width,
                        y: (1.0 - bb.maxY) * size.height,
                        width: bb.width * size.width,
                        height: bb.height * size.height
                    )
                    return OCRLine(text: candidate.string, frame: frame)
                }
                cont.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: RecognizerError.failed(error))
            }
        }
    }

    private func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
