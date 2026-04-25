import UIKit

class CellOCR {

    private let recognizer: LineRecognizing
    private let secondary: LineRecognizing?
    private let enhance: (UIImage, ImageEnhancer.Strength) -> UIImage

    init(
        recognizer: LineRecognizing,
        secondary: LineRecognizing? = VisionLineRecognizer(),
        enhance: @escaping (UIImage, ImageEnhancer.Strength) -> UIImage = ImageEnhancer.enhance
    ) {
        self.recognizer = recognizer
        self.secondary = secondary
        self.enhance = enhance
    }

    /// Reads one cell. Chain: primary (ML Kit) on crop → primary on
    /// aggressively-enhanced crop → secondary (Apple Vision) on crop →
    /// secondary on aggressively-enhanced crop. ML Kit and Vision have
    /// complementary failure modes on dim thermal prints: values one model
    /// drops (e.g. faint 2-digit AX tokens) often pass cleanly through the
    /// other. Returns the first engine-stage that produces a shape-valid
    /// value, or nil if all four fail.
    func read(cell: CellROI, image: UIImage) async -> String? {
        if let value = await attempt(cell: cell, image: image, using: recognizer) { return value }
        let harder = enhance(image, .aggressive)
        if let value = await attempt(cell: cell, image: harder, using: recognizer) { return value }
        if let secondary {
            if let value = await attempt(cell: cell, image: image, using: secondary) { return value }
            if let value = await attempt(cell: cell, image: harder, using: secondary) { return value }
        }
        return nil
    }

    private func attempt(cell: CellROI, image: UIImage, using engine: LineRecognizing) async -> String? {
        guard let lines = try? await engine.recognize(image) else { return nil }
        for line in lines {
            let candidate = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if matchesShape(candidate, for: cell.column) {
                return candidate
            }
        }
        return nil
    }

    private func matchesShape(_ value: String, for column: CellROI.Column) -> Bool {
        switch column {
        case .sph, .cyl:
            return CellOCR.decimalRegex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ) != nil
        case .ax:
            guard let n = Int(value) else { return false }
            return n >= 1 && n <= 180
        }
    }

    private static let decimalRegex: NSRegularExpression = {
        // Accept "-1.25" / "0.50" (with dot) OR dotless 3-4 digit forms
        // (-125- / 050 / 1225). ML Kit routinely drops the decimal point
        // on dim thermal prints; the downstream ReadingNormalizer
        // reinserts it. 2-digit dotless values are REJECTED: they are
        // almost always truncated fragments of the real reading (e.g.
        // "50" from "2.50") that reshape would silently flip into "0.50"
        // — see ROIPipelineExtractor.decimalRegex for the full rationale.
        try! NSRegularExpression(pattern: #"^[-+]?(?:\d{1,2}\.\d{2}|\d{3,4})$"#)
    }()
}
