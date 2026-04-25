import Foundation

enum AxisMath {
    static func circularDiff(_ a: Int, _ b: Int) -> Int {
        let raw = abs(a - b) % 180
        return min(raw, 180 - raw)
    }

    static func toleranceForCyl(_ cyl: Double) -> Double {
        let mag = abs(cyl)
        if mag <= 0.25 { return Constants.axisToleranceCylUnder025 }
        if mag <= 0.50 { return Constants.axisToleranceCyl025To050 }
        if mag <= 1.00 { return Constants.axisToleranceCyl050To100 }
        if mag <= 2.00 { return Constants.axisToleranceCyl100To200 }
        return Constants.axisToleranceCylOver200
    }
}
