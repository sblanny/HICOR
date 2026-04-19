import UIKit

class CellOCR {

    private let recognizer: LineRecognizing
    private let enhance: (UIImage, ImageEnhancer.Strength) -> UIImage

    init(
        recognizer: LineRecognizing,
        enhance: @escaping (UIImage, ImageEnhancer.Strength) -> UIImage = ImageEnhancer.enhance
    ) {
        self.recognizer = recognizer
        self.enhance = enhance
    }

    /// Reads one cell. Runs ML Kit on the crop; if no line passes the
    /// column-appropriate shape check, re-runs on an aggressively enhanced
    /// copy of the crop. Returns the first passing value, or nil after the
    /// single retry also fails.
    func read(cell: CellROI, image: UIImage) async -> String? {
        if let value = await attempt(cell: cell, image: image) { return value }
        let harder = enhance(image, .aggressive)
        return await attempt(cell: cell, image: harder)
    }

    private func attempt(cell: CellROI, image: UIImage) async -> String? {
        guard let lines = try? await recognizer.recognize(image) else { return nil }
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
        // Accept "-1.25" / "0.50" (with dot) OR dotless "-125" / "050" / "125".
        // ML Kit routinely drops the decimal point on dim thermal prints; the
        // downstream ReadingNormalizer reinserts it. 2-4 digit dotless forms
        // cover values from 0.00 (-000-) to 9.75 (975) and occasional "1225"
        // for 12.25 on high-sphere patients.
        try! NSRegularExpression(pattern: #"^[-+]?(?:\d{1,2}\.\d{2}|\d{2,4})$"#)
    }()
}
