import SwiftUI

struct PrescriptionAnalysisView: View {
    let refraction: PatientRefraction
    let results: [PrintoutResult]

    @Environment(SyncCoordinator.self) private var sync
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                    photoCard(index: idx, result: result)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .navigationTitle("Patient #\(refraction.patientNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(refraction.sessionLocation)
                .font(.subheadline.weight(.semibold))
            Text(refraction.sessionDate, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if refraction.pd > 0 {
                    Label("PD \(Int(refraction.pd)) mm", systemImage: "ruler")
                        .font(.caption)
                        .foregroundStyle(refraction.pdManualEntry ? .orange : .secondary)
                }
                if refraction.consistencyWarningOverridden {
                    Label("Override applied", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func photoCard(index: Int, result: PrintoutResult) -> some View {
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

            eyeSectionOrPlaceholder(label: "Right (OD)", reading: result.rightEye, starConfidence: result.handheldStarConfidenceRight)
            eyeSectionOrPlaceholder(label: "Left (OS)", reading: result.leftEye, starConfidence: result.handheldStarConfidenceLeft)
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
            Text(formatDiopter(sph)).frame(width: 60, alignment: .leading)
            Text(isSphOnly ? "—" : formatDiopter(cyl)).frame(width: 60, alignment: .leading)
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

    private func formatDiopter(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", value))"
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack {
                if saving {
                    ProgressView().progressViewStyle(.circular).tint(.white)
                }
                Text(saving ? "Saving…" : "Save & Return")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(saving)
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(.background)
    }

    private func save() async {
        saving = true
        await sync.save(refraction)
        saving = false
        NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
    }
}

extension Notification.Name {
    static let hicorReturnToRoot = Notification.Name("hicor.returnToRoot")
}
