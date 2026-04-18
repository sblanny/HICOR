import UIKit

final class ROIPipelineExtractor: TextExtracting {

    typealias RectifyFn = (UIImage) async -> UIImage?
    typealias EnhanceFn = (UIImage, ImageEnhancer.Strength) -> UIImage

    private let rectify: RectifyFn
    private let enhance: EnhanceFn
    private let anchorDetector: AnchorDetector
    private let cellOCR: CellOCR
    private let fallback: TextExtracting
    private let layout: CellLayout
    private let paddingFraction: CGFloat

    init(
        rectify: @escaping RectifyFn = DocumentRectifier.rectify,
        enhance: @escaping EnhanceFn = ImageEnhancer.enhance,
        anchorDetector: AnchorDetector? = nil,
        cellOCR: CellOCR? = nil,
        fallback: TextExtracting = MLKitTextExtractor(),
        layout: CellLayout = .grk6000Desktop,
        paddingFraction: CGFloat = 0.10
    ) {
        self.rectify = rectify
        self.enhance = enhance
        let recognizer = MLKitLineRecognizer()
        self.anchorDetector = anchorDetector ?? AnchorDetector(recognizer: recognizer)
        self.cellOCR = cellOCR ?? CellOCR(recognizer: recognizer)
        self.fallback = fallback
        self.layout = layout
        self.paddingFraction = paddingFraction
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        guard let rectified = await rectify(image) else {
            return try await fallbackOrThrow(image)
        }

        let enhanced = enhance(rectified, .standard)

        let anchors: Anchors
        do {
            anchors = try await anchorDetector.detectAnchors(in: enhanced)
        } catch {
            return try await fallbackOrThrow(image)
        }

        let cells = layout.cells(given: anchors)
        let crops = CellROIExtractor.crop(image: enhanced, cells: cells, paddingFraction: paddingFraction)

        var values: [CellROI: String] = [:]
        var missing: [String] = []
        for (cell, crop) in crops {
            if let value = await cellOCR.read(cell: cell, image: crop) {
                values[cell] = value
            } else {
                missing.append(cellLabel(cell))
            }
        }
        // Any cell that didn't even get cropped (rectangle fell entirely
        // outside the image bounds) is also missing.
        let croppedSet = Set(crops.map { $0.0 })
        for cell in cells where !croppedSet.contains(cell) {
            missing.append(cellLabel(cell))
        }

        if !missing.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: missing)
        }

        let rowBased = assembleRowLines(values: values)
        return ExtractedText(
            rowBased: rowBased,
            columnBased: rowBased,
            preprocessedImageData: enhanced.jpegData(compressionQuality: 0.85),
            boxes: [],
            revisionUsed: 0,
            variant: .raw
        )
    }

    func extractText(
        from image: UIImage,
        variant: PreprocessingVariant,
        revision: Int
    ) async throws -> ExtractedText {
        try await extractText(from: image)
    }

    // MARK: - Private helpers

    private func fallbackOrThrow(_ image: UIImage) async throws -> ExtractedText {
        let fbText = try await fallback.extractText(from: image)
        if fbText.rowBased.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: ["fallback produced no text"])
        }
        let missing = fallbackMissingCells(fbText.rowBased)
        if !missing.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: missing)
        }
        return fbText
    }

    /// Checks that fallback output contains the expected structure: one
    /// section marker per eye plus four data lines per eye (3 readings + AVG).
    /// Returns a list of human-readable missing-section labels.
    private func fallbackMissingCells(_ lines: [String]) -> [String] {
        var missing: [String] = []
        for (marker, eyeLabel) in [("[R]", "right"), ("[L]", "left")] {
            guard let idx = lines.firstIndex(of: marker) else {
                missing.append("\(eyeLabel) section marker")
                continue
            }
            let sectionEnd = min(idx + 5, lines.count)
            let section = Array(lines[(idx + 1)..<sectionEnd])
            let readingLines = section.filter { !$0.hasPrefix("AVG") && !$0.isEmpty }
            let avgLines = section.filter { $0.hasPrefix("AVG") }
            if readingLines.count < 3 { missing.append("\(eyeLabel) readings (<3)") }
            if avgLines.isEmpty { missing.append("\(eyeLabel) AVG") }
        }
        return missing
    }

    private func assembleRowLines(values: [CellROI: String]) -> [String] {
        var lines: [String] = []
        for eye in [CellROI.Eye.right, .left] {
            lines.append(eye == .right ? "[R]" : "[L]")
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                let sph = values[CellROI(eye: eye, column: .sph, row: row, rect: .zero)] ?? ""
                let cyl = values[CellROI(eye: eye, column: .cyl, row: row, rect: .zero)] ?? ""
                let ax  = values[CellROI(eye: eye, column: .ax,  row: row, rect: .zero)] ?? ""
                let prefix = row == .avg ? "AVG " : ""
                lines.append("\(prefix)\(sph) \(cyl) \(ax)")
            }
        }
        return lines
    }

    private func cellLabel(_ cell: CellROI) -> String {
        "\(cell.eye.rawValue) \(cell.column.rawValue) \(cell.row.rawValue)"
    }
}
