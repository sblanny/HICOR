import UIKit

/// Locates the GRK-6000 printout's PD value from raw OCR lines.
///
/// PD lives outside the readings cell grid — it prints below the [L] eye
/// section as "PD: NN mm" — so the ROI cell extractor never sees it. Without
/// this locator the analysis screen renders "—" for PD on every device
/// capture, even when ML Kit recognized the label and digits cleanly.
///
/// Two extraction modes:
/// 1. Single-line: ML Kit groups "PD: 64 mm" into one element. The label,
///    value, and unit all live in `OCRLine.text`.
/// 2. Multi-line: ML Kit splits into "PD:" / "59" / "mm" as three separate
///    elements (observed on real-device captures). The locator stitches
///    them positionally — same y band, value to the right of the label,
///    closest candidate wins.
enum PDLocator {

    /// Physiological PD bounds. 40 mm covers small children, 90 mm covers
    /// the wide-set extreme. Anything outside this window is OCR garbage
    /// (a stray axis value, a year on a date stamp, a 4-digit serial
    /// fragment) and must not be reported as PD.
    private static let plausibleRange: ClosedRange<Double> = 40.0...90.0

    static func locate(in lines: [OCRLine]) -> Double? {
        if let value = singleLineMatch(in: lines) { return value }
        return multiLineMatch(in: lines)
    }

    private static let singleLineRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)\bPD\b\s*[:=]?\s*(\d{2,3})"#)
    }()

    private static let labelOnlyRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^\s*PD\s*[:=]?\s*$"#)
    }()

    private static let pureIntegerRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\s*(\d{2,3})\s*$"#)
    }()

    private static func singleLineMatch(in lines: [OCRLine]) -> Double? {
        for line in lines {
            let text = line.text
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = singleLineRegex.firstMatch(in: text, range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[captureRange]),
                  plausibleRange.contains(value) else { continue }
            return value
        }
        return nil
    }

    private static func multiLineMatch(in lines: [OCRLine]) -> Double? {
        let labels = lines.filter { line in
            let text = line.text
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return labelOnlyRegex.firstMatch(in: text, range: range) != nil
        }
        for label in labels {
            // y band: ±0.75 of label height covers the small drift between
            // label/value/unit elements that ML Kit places on the same
            // printed row, but rejects elements from rows above/below
            // (axis values, AVG row tokens, etc).
            let yBand = max(label.frame.height * 0.75, 30)
            // Numeric must be to the right of the label's center — left-side
            // candidates (axis bleeding from the readings column) get
            // rejected.
            let xMinExclusive = label.frame.midX

            let candidates: [(line: OCRLine, value: Double)] = lines.compactMap { other in
                guard other != label else { return nil }
                let text = other.text
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                guard pureIntegerRegex.firstMatch(in: text, range: range) != nil,
                      let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                      plausibleRange.contains(value),
                      abs(other.frame.midY - label.frame.midY) < yBand,
                      other.frame.midX > xMinExclusive else { return nil }
                return (other, value)
            }

            if let nearest = candidates.min(by: { lhs, rhs in
                abs(lhs.line.frame.midX - label.frame.midX)
                    < abs(rhs.line.frame.midX - label.frame.midX)
            }) {
                return nearest.value
            }
        }
        return nil
    }
}
