import SwiftUI

/// Read-only card that renders every parsed reading for one printout:
/// per-row R1/R2/R3 plus the on-printout AVG (or * on handheld). Used on the
/// post-OCR analysis screen and on the disagreement-review screen so the
/// operator always sees what the pipeline extracted — not just a summary.
struct PrintoutReadingsCard: View {
    let index: Int
    let result: PrintoutResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photo \(index + 1)")
                    .font(.headline)
                Spacer()
                Text(result.machineType == .desktop ? "Desktop" : "Handheld")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
            }

            eyeSectionOrPlaceholder(
                label: "Right (OD)",
                reading: result.rightEye,
                starConfidence: result.handheldStarConfidenceRight
            )
            eyeSectionOrPlaceholder(
                label: "Left (OS)",
                reading: result.leftEye,
                starConfidence: result.handheldStarConfidenceLeft
            )
            if let pd = result.pd {
                Text("PD: \(Int(pd)) mm").font(.caption)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func eyeSectionOrPlaceholder(label: String, reading: EyeReading?, starConfidence: Int?) -> some View {
        if let r = reading, !r.readings.isEmpty {
            eyeSection(label: label, reading: r, starConfidence: starConfidence)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline.weight(.semibold))
                Text("No readings captured")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func eyeSection(label: String, reading: EyeReading, starConfidence: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            ForEach(reading.readings) { r in
                rxRow(sph: r.sph, cyl: r.cyl, ax: r.ax, lowConfidence: r.lowConfidence, isSphOnly: r.isSphOnly)
            }
            if let avgSPH = reading.machineAvgSPH,
               let avgCYL = reading.machineAvgCYL,
               let avgAX  = reading.machineAvgAX {
                HStack(spacing: 8) {
                    Text(reading.machineType == .desktop ? "AVG" : "*")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                    rxRow(sph: avgSPH, cyl: avgCYL, ax: avgAX, lowConfidence: false, isSphOnly: false)
                    if let conf = starConfidence {
                        Text("conf \(conf)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func rxRow(sph: Double, cyl: Double, ax: Int, lowConfidence: Bool, isSphOnly: Bool) -> some View {
        HStack(spacing: 12) {
            Text(PrintoutReadingsCard.formatDiopter(sph)).frame(width: 60, alignment: .leading)
            Text(isSphOnly ? "—" : PrintoutReadingsCard.formatDiopter(cyl)).frame(width: 60, alignment: .leading)
            Text(isSphOnly ? "—" : "\(ax)°").frame(width: 50, alignment: .leading)
            if lowConfidence {
                Text("E")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.system(.body, design: .monospaced))
        .opacity(lowConfidence ? 0.55 : 1.0)
    }

    static func formatDiopter(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))"
    }
}
