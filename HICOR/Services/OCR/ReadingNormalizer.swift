import Foundation

enum ReadingNormalizer {

    static let inventoryCylinders: [Double] = [-2.00, -1.50, -1.00, -0.50, 0.00]

    static func normalize(sph: Double) -> Double {
        roundToQuarterDiopter(sph)
    }

    static func normalize(cyl: Double) -> Double {
        roundToQuarterDiopter(cyl)
    }

    static func isCylInsideInventoryRange(_ cyl: Double) -> Bool {
        let normalized = normalize(cyl: cyl)
        return inventoryCylinders.contains { abs($0 - normalized) < 0.001 }
    }

    static func normalize(ax: Int) -> Int {
        if ax < 1 { return 1 }
        if ax > 180 { return 180 }
        return ax
    }

    static func normalizeOCRString(_ raw: String) -> String {
        let tokens = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let normalized = tokens.map { token -> String in
            isNumericCandidate(token) ? normalizeNumericToken(token) : token
        }
        // Axis-fragment repair. ML Kit occasionally splits a 3-digit axis like
        // 179 into two adjacent tokens "1" and "79" on faint thermal prints,
        // which the shape gate rejects. Merge a standalone "1" token followed
        // by a 2-digit integer whose combined value falls in the legal axis
        // range (100–180). Restricted to leading digit "1" because no valid
        // 3-digit axis starts with any other digit.
        let merged = mergeAxisFragments(normalized)
        return merged.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mergeAxisFragments(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t == "1",
               i + 1 < tokens.count,
               tokens[i + 1].count == 2,
               tokens[i + 1].allSatisfy(\.isNumber),
               let nn = Int(tokens[i + 1]), nn >= 0, nn <= 80 {
                result.append("1" + tokens[i + 1])
                i += 2
            } else {
                result.append(t)
                i += 1
            }
        }
        return result
    }

    static func isNumericCandidate(_ token: String) -> Bool {
        let reserved: Set<String> = [
            "SPH", "CYL", "AX", "AQ", "REF", "PD", "VD", "AVG", "GRK",
            "[R]", "[L]", "<R>", "<L>", "E", "MM"
        ]
        if reserved.contains(token.uppercased()) { return false }

        let confusionLetters: Set<Character> = ["O", "o", "l", "I", "S", "A"]
        // Comma is treated as structural so tokens like "0,75" survive the
        // numeric-candidate gate; normalizeNumericToken then substitutes it
        // back to "." Autorefractor printouts never contain legitimate commas.
        let structural: Set<Character> = ["+", "-", ".", "*", ","]
        var hasDigit = false
        for ch in token {
            if ch.isNumber { hasDigit = true; continue }
            if structural.contains(ch) { continue }
            if confusionLetters.contains(ch) { continue }
            return false
        }
        return hasDigit
    }

    static func normalizeNumericToken(_ token: String) -> String {
        var s = token
        s = s.replacingOccurrences(of: "O", with: "0")
        s = s.replacingOccurrences(of: "o", with: "0")
        s = s.replacingOccurrences(of: "l", with: "1")
        s = s.replacingOccurrences(of: "I", with: "1")
        s = s.replacingOccurrences(of: "S", with: "5")
        // ML Kit occasionally substitutes capital A for digit 4 on thermal
        // desktop printouts (thin-stroke glyph confusion). Only applied
        // inside tokens flagged numeric by isNumericCandidate.
        s = s.replacingOccurrences(of: "A", with: "4")
        // Comma → period. ML Kit occasionally emits "0,75" instead of "0.75"
        // on thermal captures (European-locale glyph confusion).
        s = s.replacingOccurrences(of: ",", with: ".")

        // Dropped-decimal repair. ML Kit occasionally loses the decimal point
        // on thermal-paper decimals like "4.25" → "425", leaving a bare 3-
        // digit integer the shape gate then rejects. A 3-digit token whose
        // integer value exceeds 180 cannot be a legitimate axis (AX range is
        // 1-180), so it must be a diopter with a missing dot. We restore the
        // dot after the first digit. Values ≤ 180 are left alone because
        // they could be real axes (e.g. 108, 150, 175).
        if s.count == 3,
           s.allSatisfy(\.isNumber),
           let intValue = Int(s), intValue > 180 {
            let i = s.index(after: s.startIndex)
            s = s[..<i] + "." + s[i...]
        }
        return s
    }

    private static func roundToQuarterDiopter(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }
}
