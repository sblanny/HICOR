import UIKit

final class ROIPipelineExtractor: TextExtracting {

    typealias RectifyFn = (UIImage) async -> UIImage?
    typealias EnhanceFn = (UIImage, ImageEnhancer.Strength) -> UIImage

    private let rectify: RectifyFn
    private let enhance: EnhanceFn
    private let lineRecognizer: LineRecognizing
    private let anchorDetector: AnchorDetector
    private let cellOCR: CellOCR
    private let fallback: TextExtracting
    private let layout: CellLayout
    private let paddingFraction: CGFloat

    init(
        rectify: @escaping RectifyFn = DocumentRectifier.rectify,
        enhance: @escaping EnhanceFn = ImageEnhancer.enhance,
        lineRecognizer: LineRecognizing? = nil,
        anchorDetector: AnchorDetector? = nil,
        cellOCR: CellOCR? = nil,
        fallback: TextExtracting = MLKitTextExtractor(),
        layout: CellLayout = .grk6000Desktop,
        paddingFraction: CGFloat = 0.10
    ) {
        self.rectify = rectify
        self.enhance = enhance
        let recognizer = lineRecognizer ?? MLKitLineRecognizer()
        self.lineRecognizer = recognizer
        self.anchorDetector = anchorDetector ?? AnchorDetector(recognizer: recognizer)
        self.cellOCR = cellOCR ?? CellOCR(recognizer: recognizer)
        self.fallback = fallback
        self.layout = layout
        self.paddingFraction = paddingFraction
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        // Rectification disabled 2026-04-18: Vision rectangle detection
        // consistently corrupts the image on the real GRK-6000 fixtures
        // (ML Kit then finds only ~3 tokens on the rectified output). The
        // framing guide now does the work of keeping the slip roughly
        // square-to-camera; we operate on the raw capture instead.
        _ = await rectify  // retain storage ref for tests; unused in prod path
        print("ROIPipeline: input size=\(image.size) orientation=\(image.imageOrientation.rawValue)")
        let oriented = orientSlipToPortrait(image)
        print("ROIPipeline: oriented size=\(oriented.size)")
        let enhanced = enhance(oriented, .standard)
        print("ROIPipeline: enhanced size=\(enhanced.size)")

        // Run ML Kit once against the full enhanced image and reuse the
        // element list for both anchor detection and per-cell value picking.
        // Per-cell re-OCR on narrow column crops is unreliable — ML Kit
        // needs surrounding context and often yields nothing on a crop it
        // reads cleanly at full size.
        let lines: [OCRLine]
        do {
            lines = try await lineRecognizer.recognize(enhanced)
        } catch {
            print("ROIPipeline: line recognition failed \(error) → fallback")
            return try await fallbackOrThrow(image)
        }

        let anchors: Anchors
        do {
            anchors = try anchorDetector.detectAnchors(from: lines)
            print("ROIPipeline: anchors detected r.eye=\(anchors.right.eyeMarker) r.avg=\(anchors.right.avg) l.eye=\(anchors.left.eyeMarker) l.avg=\(anchors.left.avg)")
        } catch {
            print("ROIPipeline: anchor detection failed \(error) → fallback")
            return try await fallbackOrThrow(image)
        }

        let cells = layout.cells(given: anchors)
        let (pickedValues, unresolved) = pickCellValues(cells: cells, lines: lines)
        print("ROIPipeline: element-picked \(pickedValues.count) / \(cells.count); unresolved=\(unresolved.count)")

        var values = pickedValues
        // For any cell the full-image pass could not populate, fall back to
        // cropping that cell and re-running ML Kit with aggressive
        // enhancement. Covers cases where a value token was fused with an
        // adjacent one at full size (e.g. "-1.00172" = CYL + AX merged).
        if !unresolved.isEmpty {
            let crops = CellROIExtractor.crop(image: enhanced, cells: unresolved, paddingFraction: paddingFraction)
            for (cell, crop) in crops {
                if let value = await cellOCR.read(cell: cell, image: crop) {
                    values[cell] = value
                }
            }
        }

        let missing = cells.filter { values[$0] == nil }.map(cellLabel)
        print("ROIPipeline: values=\(values.count) missing=\(missing.count) missingLabels=\(missing)")

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

    /// For each cell, find the full-image element whose center lies inside
    /// the cell rectangle and whose text passes the column's shape check.
    /// If several match, prefer the one closest to the cell center. Returns
    /// the resolved values plus the list of cells still unresolved (caller
    /// can fall back to per-cell re-OCR).
    private func pickCellValues(
        cells: [CellROI],
        lines: [OCRLine]
    ) -> ([CellROI: String], [CellROI]) {
        var resolved: [CellROI: String] = [:]
        var unresolved: [CellROI] = []
        for cell in cells {
            let inside = lines.filter { cell.rect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            let passing = inside.compactMap { line -> (OCRLine, String)? in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return matchesShape(trimmed, for: cell.column) ? (line, trimmed) : nil
            }
            if let best = passing.min(by: { lhs, rhs in
                let dl = hypot(lhs.0.frame.midX - cell.rect.midX, lhs.0.frame.midY - cell.rect.midY)
                let dr = hypot(rhs.0.frame.midX - cell.rect.midX, rhs.0.frame.midY - cell.rect.midY)
                return dl < dr
            }) {
                resolved[cell] = best.1
            } else {
                unresolved.append(cell)
            }
        }
        return (resolved, unresolved)
    }

    private func matchesShape(_ value: String, for column: CellROI.Column) -> Bool {
        switch column {
        case .sph, .cyl:
            let range = NSRange(value.startIndex..., in: value)
            return ROIPipelineExtractor.decimalRegex.firstMatch(in: value, range: range) != nil
        case .ax:
            guard let n = Int(value) else { return false }
            return n >= 1 && n <= 180
        }
    }

    // Shape regex mirrors CellOCR's. Duplicated here (not shared) because
    // the two have different downstream contracts: CellOCR's regex governs
    // a single re-OCR crop, while this one gates element picking against
    // the full-image line list where whole-number angles (AX) coexist with
    // decimal sphere/cyl values.
    private static let decimalRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[-+]?(?:\d{1,2}\.\d{2}|\d{2,4})$"#)
    }()

    private func fallbackOrThrow(_ image: UIImage) async throws -> ExtractedText {
        let fbText = try await fallback.extractText(from: image)
        print("ROIPipeline: fallback rowBased (\(fbText.rowBased.count) lines):")
        for line in fbText.rowBased { print("  | \(line)") }
        // Anchor-detection failure on a thermal GRK-6000 slip means the
        // capture is unusable — trying to reconstruct readings from the
        // fallback extractor's row-based text is unreliable on this layout.
        // Throw incompleteCells so the UI prompts the user to recapture.
        throw OCRService.OCRError.incompleteCells(missing: ["anchor detection failed — recapture required"])
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

    /// Bakes any EXIF orientation into the bitmap so downstream stages work
    /// in a single coordinate space. The slip is already portrait in the
    /// captured image (the camera applies orientation via EXIF); we just
    /// need to collapse that into the raw pixels before per-cell cropping,
    /// which operates on `UIImage.cgImage` directly.
    private func orientSlipToPortrait(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
