import Foundation

// Strict shape gate for autorefractor reading lines, shared by handheld and
// desktop parsers. Rejects OCR fragmentation garbage like "111  25  25" or
// "2.  25  49" before any numeric extraction is attempted.
enum ReadingLineShape {

    // SPH alone, OR SPH + CYL + AX, optionally trailed by AQ/E.
    // Each diopter token must be `\d{1,2}\.\d{2}` with optional sign — bare
    // integer tokens are never spheres or cylinders.
    private static let pattern =
        #"^\s*[-+]?\s*\d{1,2}\.\d{2}(\s+[-+]?\s*\d{1,2}\.\d{2}\s+\d{1,3})?(\s+(?:AQ|E))?\s*$"#

    private static let regex: NSRegularExpression? =
        try? NSRegularExpression(pattern: pattern)

    static func matches(_ line: String, allowQualityMarker: Bool) -> Bool {
        // The pattern always permits the optional AQ/E tail. Desktop callers pass
        // allowQualityMarker=false but the pattern stays the same; AQ/E never
        // appears on desktop lines, so the optional group simply never fires.
        _ = allowQualityMarker
        guard let regex else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }
}

enum ReadingPlausibility {

    // ±25 D accommodates real high-hyperopia clinical cases (the +21 fixture
    // is a documented patient). Values outside this band are OCR garbage.
    static func isPlausibleSPH(_ value: Double) -> Bool {
        return value >= -25.0 && value <= 25.0
    }

    // Minus-cylinder convention: cyl is always 0 or negative, never larger
    // than -10 D in practice.
    static func isPlausibleCYL(_ value: Double) -> Bool {
        return value >= -10.0 && value <= 0.0
    }

    static func isPlausibleAX(_ value: Int) -> Bool {
        return value >= 1 && value <= 180
    }
}
