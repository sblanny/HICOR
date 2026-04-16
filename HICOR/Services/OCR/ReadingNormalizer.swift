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
        var s = raw
        s = s.replacingOccurrences(of: "O", with: "0")
        s = s.replacingOccurrences(of: "o", with: "0")
        s = s.replacingOccurrences(of: "l", with: "1")
        s = s.replacingOccurrences(of: "I", with: "1")
        s = s.replacingOccurrences(of: "S", with: "5")
        s = s.replacingOccurrences(of: "B", with: "8")
        s = s.replacingOccurrences(of: "  ", with: " ")
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func roundToQuarterDiopter(_ value: Double) -> Double {
        (value * 4).rounded() / 4
    }
}
