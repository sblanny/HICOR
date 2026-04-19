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
        let oriented = orientSlipToPortrait(image)
        let enhanced = enhance(oriented, .standard)

        // Run ML Kit once against the full enhanced image and reuse the
        // element list for both anchor detection and per-cell value picking.
        // Per-cell re-OCR on narrow column crops is unreliable — ML Kit
        // needs surrounding context and often yields nothing on a crop it
        // reads cleanly at full size.
        let lines: [OCRLine]
        do {
            lines = try await lineRecognizer.recognize(enhanced)
        } catch {
            return try await fallbackOrThrow(image)
        }

        let anchors: Anchors
        do {
            anchors = try anchorDetector.detectAnchors(from: lines)
        } catch {
            return try await fallbackOrThrow(image)
        }

        let cells = layout.cells(given: anchors)
        let splitLines = splitMergedDecimalLines(lines)
        let (pickedValues, unresolved) = pickCellValues(cells: cells, lines: splitLines)

        var values = pickedValues
        // For any cell the full-image pass could not populate, fall back to
        // cropping that cell and re-running ML Kit with aggressive
        // enhancement. Covers cases where a value token was fused with an
        // adjacent one at full size (e.g. "-1.00172" = CYL + AX merged).
        if !unresolved.isEmpty {
            let crops = CellROIExtractor.crop(image: enhanced, cells: unresolved, paddingFraction: paddingFraction)
            for (cell, crop) in crops {
                if let value = await cellOCR.read(cell: cell, image: crop) {
                    let normalized = ReadingNormalizer.normalizeNumericToken(value)
                    values[cell] = reshape(normalized, for: cell.column)
                }
            }
        }

        // Apply column-specific sign conventions to the full value map
        // (pick + re-OCR results combined) so CYL/SPH signs are consistent
        // regardless of how a cell was populated.
        values = applySignConventions(to: values, cells: cells, lines: lines)

        let missing = cells.filter { values[$0] == nil }.map(cellLabel)
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

    /// For each cell, find elements inside the cell rect and produce a
    /// normalized value. Strategy (in order):
    ///   1. Merge fragments (if ≥2 elements inside) with digit-boundary
    ///      overlap removal — covers ML Kit splitting "178" into ["17","78"]
    ///      or "179" into ["1","79"] on dim thermal AX cells.
    ///   2. Single element whose normalized text passes the column shape,
    ///      preferring the element closest to the cell center.
    /// Each successful pick is then `reshape`d (dotless → dotted decimal
    /// for SPH/CYL) and run through `applySignConventions` to reinsert
    /// column-specific sign prefixes ML Kit drops on dim captures.
    private func pickCellValues(
        cells: [CellROI],
        lines: [OCRLine]
    ) -> ([CellROI: String], [CellROI]) {
        var resolved: [CellROI: String] = [:]
        var unresolved: [CellROI] = []
        for cell in cells {
            // Widen the X search by 30% on each side so sign-digit fragments
            // ML Kit places just outside the header-derived cell rect still
            // get included. Y stays strict to avoid pulling values from the
            // row above or below. 30% is safe because SPH→CYL→AX column gaps
            // on the GRK-6000 are ~1.5-2× cell width.
            let xSlop = cell.rect.width * 0.3
            let wideRect = cell.rect.insetBy(dx: -xSlop, dy: 0)
            let inside = lines
                .filter { wideRect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                .sorted { $0.frame.midX < $1.frame.midX }

            // Strategy 1: merge fragments with overlap removal first so
            // "17"+"79" becomes "179" (not a truncated "17").
            if inside.count >= 2 {
                let fragments = inside.map {
                    $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let merged = mergeFragmentsWithOverlap(fragments)
                let normalized = ReadingNormalizer.normalizeNumericToken(merged)
                if matchesShape(normalized, for: cell.column) {
                    resolved[cell] = reshape(normalized, for: cell.column)
                    continue
                }
            }

            // Strategy 2: single element passes shape after normalization.
            // Prefer elements that already carry a sign (SPH column only):
            // multiple detections of the same glyph are common on dim prints
            // and the signed variant is always the correct reading.
            let singleMatches = inside.compactMap { line -> (OCRLine, String)? in
                let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = ReadingNormalizer.normalizeNumericToken(trimmed)
                return matchesShape(normalized, for: cell.column) ? (line, normalized) : nil
            }
            if let best = singleMatches.min(by: { lhs, rhs in
                let lSigned = (lhs.1.hasPrefix("+") || lhs.1.hasPrefix("-")) ? 0 : 1
                let rSigned = (rhs.1.hasPrefix("+") || rhs.1.hasPrefix("-")) ? 0 : 1
                if lSigned != rSigned { return lSigned < rSigned }
                let dl = hypot(lhs.0.frame.midX - cell.rect.midX, lhs.0.frame.midY - cell.rect.midY)
                let dr = hypot(rhs.0.frame.midX - cell.rect.midX, rhs.0.frame.midY - cell.rect.midY)
                return dl < dr
            }) {
                resolved[cell] = reshape(best.1, for: cell.column)
                continue
            }

            unresolved.append(cell)
        }
        return (resolved, unresolved)
    }

    /// Two-pass sign reconciliation over the full cell map (combines
    /// pick-time picks + CellOCR re-OCR fallback picks). Pass 1 applies
    /// CYL negativity and SPH direct-sign (embedded or adjacent fragment
    /// element). Pass 2 propagates the dominant SPH section sign to any
    /// still-unsigned SPH cell — a patient's sphere readings don't flip
    /// sign row-to-row on the same eye.
    private func applySignConventions(
        to values: [CellROI: String],
        cells: [CellROI],
        lines: [OCRLine]
    ) -> [CellROI: String] {
        var out = values
        for cell in cells where out[cell] != nil {
            switch cell.column {
            case .cyl:
                out[cell] = applyCYLSign(out[cell]!)
            case .sph:
                out[cell] = applySPHDirectSign(
                    value: out[cell]!,
                    cell: cell,
                    lines: lines
                )
            case .ax:
                break
            }
        }
        for cell in cells where cell.column == .sph && out[cell] != nil {
            let v = out[cell]!
            if v.hasPrefix("+") || v.hasPrefix("-") { continue }
            if let sign = sectionSPHSign(for: cell, resolved: out) {
                out[cell] = sign + v
            }
        }
        return out
    }

    /// When ML Kit bounds a whole row of printer output in a single element
    /// (e.g. "0.25-1.00" spanning SPH + CYL on tight thermal prints), its
    /// midX falls in the gap between the two cell rects and the picker
    /// assigns it to neither. Detect "X.XX-Y.YY" merges and emit two
    /// synthetic lines with x-ratios proportional to each half's character
    /// count so the midX of each synthetic line lands inside its respective
    /// column cell.
    private func splitMergedDecimalLines(_ lines: [OCRLine]) -> [OCRLine] {
        let pattern = try! NSRegularExpression(pattern: #"^(\d{1,2}\.\d{2})(-)(\d{1,2}\.\d{2})$"#)
        var out: [OCRLine] = []
        for line in lines {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = pattern.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges == 4,
                  let leftRange = Range(match.range(at: 1), in: trimmed),
                  let rightRange = Range(match.range(at: 3), in: trimmed) else {
                out.append(line); continue
            }
            let leftText = String(trimmed[leftRange])
            let rightText = "-" + String(trimmed[rightRange])
            let total = CGFloat(trimmed.count)
            let leftFraction = CGFloat(leftText.count) / total
            let rightFraction = CGFloat(rightText.count) / total
            let leftFrame = CGRect(
                x: line.frame.minX,
                y: line.frame.minY,
                width: line.frame.width * leftFraction,
                height: line.frame.height
            )
            let rightFrame = CGRect(
                x: line.frame.minX + line.frame.width * (1.0 - rightFraction),
                y: line.frame.minY,
                width: line.frame.width * rightFraction,
                height: line.frame.height
            )
            out.append(OCRLine(text: leftText, frame: leftFrame))
            out.append(OCRLine(text: rightText, frame: rightFrame))
        }
        return out
    }

    /// Concatenate digit fragments in x-order, dropping one character at
    /// each boundary when the left fragment's last char equals the right
    /// fragment's first char. Covers ML Kit splitting a 3-digit AX like
    /// "178" into two overlapping crops ["17", "78"] that share the
    /// middle glyph. Non-overlap concatenation (e.g. "1"+"79" = "179")
    /// works unchanged.
    private func mergeFragmentsWithOverlap(_ fragments: [String]) -> String {
        var result = ""
        for frag in fragments {
            if let last = result.last, let first = frag.first, last == first {
                result += frag.dropFirst()
            } else {
                result += frag
            }
        }
        return result
    }

    /// Canonicalize a shape-matched value to the test-expected form.
    /// For SPH/CYL cells a 2-4 digit dotless number is reflowed to the
    /// "#.##" decimal form (e.g. "50"→"0.50", "050"→"0.50", "125"→"1.25",
    /// "1225"→"12.25"). AX values stay as plain integers.
    private func reshape(_ value: String, for column: CellROI.Column) -> String {
        switch column {
        case .sph, .cyl:
            var sign = ""
            var body = value
            if body.hasPrefix("+") || body.hasPrefix("-") {
                sign = String(body.first!)
                body.removeFirst()
            }
            if body.contains(".") { return sign + body }
            guard (2...4).contains(body.count), body.allSatisfy(\.isNumber) else { return value }
            let frac = String(body.suffix(2))
            let whole = body.count == 2 ? "0" : String(body.prefix(body.count - 2))
            return sign + whole + "." + frac
        case .ax:
            return value
        }
    }

    /// GRK-6000 CYL column is always negative (column header is "(-)"),
    /// except the literal zero value which prints as "0.00".
    private func applyCYLSign(_ value: String) -> String {
        var core = value
        if core.hasPrefix("+") || core.hasPrefix("-") { core.removeFirst() }
        if core == "0.00" { return core }
        return "-" + core
    }

    /// Resolve an SPH cell's sign from the picked value's prefix or a
    /// "+"/"-" fragment element printed to the left within the row band.
    /// Returns the value unchanged (no sign prefix) if neither source
    /// fires — section propagation runs in a second pass.
    private func applySPHDirectSign(
        value: String,
        cell: CellROI,
        lines: [OCRLine]
    ) -> String {
        if value.hasPrefix("+") || value.hasPrefix("-") { return value }
        if let adjacent = adjacentSign(for: cell, lines: lines) {
            return adjacent + value
        }
        return value
    }

    /// Look for a "+" or "-" element in the same row band as the cell,
    /// within one cell-width to the left of the cell's left edge. ML Kit
    /// often splits tiny sign glyphs off as their own 20×20-ish elements
    /// that fall outside the numeric cell rect.
    private func adjacentSign(for cell: CellROI, lines: [OCRLine]) -> String? {
        let ySlop = cell.rect.height * 0.75
        let xMin = cell.rect.minX - cell.rect.width
        let xMax = cell.rect.minX
        return lines.first { line in
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t == "+" || t == "-" else { return false }
            return abs(line.frame.midY - cell.rect.midY) < ySlop
                && line.frame.midX >= xMin
                && line.frame.midX <= xMax
        }?.text
    }

    /// For an SPH cell with no detected sign, infer it from other SPH
    /// values in the same eye section — a patient's sphere readings
    /// across r1/r2/r3/avg are almost always same-signed.
    private func sectionSPHSign(for cell: CellROI, resolved: [CellROI: String]) -> String? {
        var positives = 0
        var negatives = 0
        for (other, value) in resolved where other.eye == cell.eye && other.column == .sph && other != cell {
            if value.hasPrefix("+") { positives += 1 }
            else if value.hasPrefix("-") { negatives += 1 }
        }
        if negatives > positives { return "-" }
        if positives > negatives { return "+" }
        return nil
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
        _ = try await fallback.extractText(from: image)
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
