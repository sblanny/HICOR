import Foundation

enum DiopterFormatter {
    /// Formats a SPH or CYL diopter value for display.
    /// Plano (0.00, including IEEE-754 -0.0) renders as " 0.00" with a
    /// leading space so the column aligns visually with `+1.50` / `-0.50`.
    /// The explicit `value == 0` collapse to `0.0` is what prevents the
    /// "+-0.00" mangling: `String(format: "%.2f", -0.0)` returns "-0.00",
    /// and a `value >= 0 ? "+" : ""` prefix on top yields "+-0.00".
    static func format(_ value: Double) -> String {
        let normalized = value == 0 ? 0.0 : value
        if normalized == 0 { return " 0.00" }
        return normalized > 0
            ? String(format: "+%.2f", normalized)
            : String(format: "%.2f", normalized)
    }

    /// Formats an axis value for monospaced column display. Pads the
    /// numeric part to three characters so 1°/2° axes don't visually
    /// shift the column relative to 3-digit axes (180°, 119°).
    static func formatAxis(_ axis: Int) -> String {
        String(format: "%3d°", axis)
    }
}
