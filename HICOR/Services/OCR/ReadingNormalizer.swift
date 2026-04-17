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
        return normalized.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isNumericCandidate(_ token: String) -> Bool {
        let reserved: Set<String> = [
            "SPH", "CYL", "AX", "AQ", "REF", "PD", "VD", "AVG", "GRK",
            "[R]", "[L]", "<R>", "<L>", "E", "MM"
        ]
        if reserved.contains(token.uppercased()) { return false }

        let confusionLetters: Set<Character> = ["O", "o", "l", "I", "S"]
        let structural: Set<Character> = ["+", "-", ".", "*"]
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
        return s
    }

    private static func roundToQuarterDiopter(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }
}
