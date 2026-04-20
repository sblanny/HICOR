import SwiftUI

struct PrescriptionAnalysisView: View {
    let refraction: PatientRefraction
    let results: [PrintoutResult]
    var droppedOutliers: [ConsistencyValidator.DroppedReading] = []
    let finalOutcome: PrescriptionCalculationOutcome

    @Environment(SyncCoordinator.self) private var sync
    @State private var saving = false
    @State private var patientNotifiedTier2 = false
    @State private var tier0BlurryVision: Tier0SymptomCheck.Answer = .unanswered
    @State private var tier0Headaches: Tier0SymptomCheck.Answer = .unanswered
    @State private var tier0Squinting: Tier0SymptomCheck.Answer = .unanswered

    private var tierPresentation: TierPresentation {
        TierPresentation.make(for: finalOutcome.overallTier)
    }

    private var tier0Decision: Tier0SymptomCheck.Decision {
        Tier0SymptomCheck.decide(
            blurryVision: tier0BlurryVision,
            headachesReading: tier0Headaches,
            squinting: tier0Squinting
        )
    }

    private var saveState: SaveGate.State {
        SaveGate.evaluate(
            outcome: finalOutcome,
            patientNotifiedTier2: patientNotifiedTier2,
            tier0Decision: tier0Decision
        )
    }

    private var phase5DroppedOutliers: [ConsistencyValidator.DroppedReading] {
        var all: [ConsistencyValidator.DroppedReading] = []
        if let r = finalOutcome.rightEye { all.append(contentsOf: r.phase5DroppedOutliers) }
        if let l = finalOutcome.leftEye  { all.append(contentsOf: l.phase5DroppedOutliers) }
        return all
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if finalOutcome.requiresManualReview {
                    manualReviewSection
                } else {
                    tierBanner
                    if finalOutcome.overallTier == .tier0NoGlassesNeeded {
                        tier0SymptomSection
                    }
                    finalPrescriptionCard
                    if tierPresentation.requiresPatientNotifiedAcknowledgement {
                        tier2AcknowledgeSection
                    }
                }

                if !finalOutcome.clinicalFlags.isEmpty {
                    clinicalFlagsSection
                }

                if !droppedOutliers.isEmpty {
                    upstreamOutlierBanner
                }

                if !phase5DroppedOutliers.isEmpty {
                    phase5OutlierBanner
                }

                pdCard

                DisclosureGroup("Per-photo readings") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                            photoCard(index: idx, result: result)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)

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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(refraction.sessionLocation)
                .font(.subheadline.weight(.semibold))
            Text(refraction.sessionDate, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            if refraction.consistencyWarningOverridden {
                Label("Override applied", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Tier banner

    private var tierBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tierPresentation.title, systemImage: iconName(for: tierPresentation.severity))
                .font(.headline)
                .foregroundStyle(color(for: tierPresentation.severity))
            Text(tierPresentation.subtitle)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color(for: tierPresentation.severity).opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color(for: tierPresentation.severity).opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Final prescription card

    private var finalPrescriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Final prescription")
                .font(.headline)
            prescriptionRow(label: "Right (OD)", rx: finalOutcome.rightEye)
            prescriptionRow(label: "Left (OS)",  rx: finalOutcome.leftEye)
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func prescriptionRow(label: String, rx: FinalPrescription?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            if let rx = rx {
                HStack(spacing: 16) {
                    Text(formatDiopter(rx.sph)).frame(width: 70, alignment: .leading)
                    Text(formatDiopter(rx.cyl)).frame(width: 70, alignment: .leading)
                    Text("\(rx.ax)°").frame(width: 50, alignment: .leading)
                }
                .font(.system(.title3, design: .monospaced))
            } else {
                Text("No final prescription computed")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tier 0 symptom check

    private var tier0SymptomSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symptom check")
                .font(.headline)
            Text("Any \"yes\" below means we should still dispense glasses.")
                .font(.caption)
                .foregroundStyle(.secondary)
            symptomRow(question: "Is your vision blurry?", answer: $tier0BlurryVision)
            symptomRow(question: "Do you get headaches when reading?", answer: $tier0Headaches)
            symptomRow(question: "Do you squint to see clearly?", answer: $tier0Squinting)
            switch tier0Decision {
            case .indeterminate:
                EmptyView()
            case .noGlassesNeeded:
                Label("No glasses needed — will save as \"no symptoms.\"",
                      systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.green)
            case .dispenseTier1:
                Label("Symptoms reported — will dispense as Tier 1.",
                      systemImage: "eyeglasses")
                    .font(.footnote)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func symptomRow(question: String, answer: Binding<Tier0SymptomCheck.Answer>) -> some View {
        HStack {
            Text(question).font(.subheadline)
            Spacer()
            Picker("", selection: answer) {
                Text("—").tag(Tier0SymptomCheck.Answer.unanswered)
                Text("No").tag(Tier0SymptomCheck.Answer.no)
                Text("Yes").tag(Tier0SymptomCheck.Answer.yes)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    // MARK: - Tier 2 acknowledgement

    private var tier2AcknowledgeSection: some View {
        Toggle(isOn: $patientNotifiedTier2) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Patient has been notified")
                    .font(.subheadline.weight(.semibold))
                Text("I told the patient this is outside our typical range (stretch fit).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            Color.orange.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Manual review

    private var manualReviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Manual review required", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("The calculator could not produce a final prescription automatically. Compare the readouts below before deciding how to proceed.")
                .font(.subheadline)
            manualReviewTable
        }
        .padding()
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }

    private var manualReviewTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo").frame(width: 50, alignment: .leading)
                Text("Eye").frame(width: 40, alignment: .leading)
                Text("SPH").frame(width: 60, alignment: .leading)
                Text("CYL").frame(width: 60, alignment: .leading)
                Text("AX").frame(width: 40, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                ForEach(manualReviewRows(for: result, photoIndex: idx), id: \.id) { row in
                    HStack {
                        Text("\(row.photoIndex + 1)").frame(width: 50, alignment: .leading)
                        Text(row.eyeLabel).frame(width: 40, alignment: .leading)
                        Text(formatDiopter(row.sph)).frame(width: 60, alignment: .leading)
                        Text(row.isSphOnly ? "—" : formatDiopter(row.cyl)).frame(width: 60, alignment: .leading)
                        Text(row.isSphOnly ? "—" : "\(row.ax)°").frame(width: 40, alignment: .leading)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    private struct ManualReviewRow {
        let id: UUID
        let photoIndex: Int
        let eyeLabel: String
        let sph: Double
        let cyl: Double
        let ax: Int
        let isSphOnly: Bool
    }

    private func manualReviewRows(for result: PrintoutResult, photoIndex: Int) -> [ManualReviewRow] {
        var rows: [ManualReviewRow] = []
        if let r = result.rightEye {
            for reading in r.readings {
                rows.append(ManualReviewRow(
                    id: reading.id, photoIndex: photoIndex, eyeLabel: "OD",
                    sph: reading.sph, cyl: reading.cyl, ax: reading.ax, isSphOnly: reading.isSphOnly
                ))
            }
        }
        if let l = result.leftEye {
            for reading in l.readings {
                rows.append(ManualReviewRow(
                    id: reading.id, photoIndex: photoIndex, eyeLabel: "OS",
                    sph: reading.sph, cyl: reading.cyl, ax: reading.ax, isSphOnly: reading.isSphOnly
                ))
            }
        }
        return rows
    }

    // MARK: - Clinical flags

    private var clinicalFlagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clinical notes")
                .font(.headline)
            ForEach(Array(finalOutcome.clinicalFlags.enumerated()), id: \.offset) { _, flag in
                flagRow(instruction: ClinicalFlagInstruction.make(for: flag))
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func flagRow(instruction: ClinicalFlagInstruction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: instruction.severity))
                .foregroundStyle(color(for: instruction.severity))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.title).font(.subheadline.weight(.semibold))
                Text(instruction.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Outlier banners

    private var upstreamOutlierBanner: some View {
        outlierBanner(
            title: "\(droppedOutliers.count) consistency exclusion\(droppedOutliers.count == 1 ? "" : "s")",
            drops: droppedOutliers
        )
    }

    private var phase5OutlierBanner: some View {
        outlierBanner(
            title: "\(phase5DroppedOutliers.count) reading\(phase5DroppedOutliers.count == 1 ? "" : "s") excluded by final aggregation",
            drops: phase5DroppedOutliers
        )
    }

    private func outlierBanner(title: String, drops: [ConsistencyValidator.DroppedReading]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⚠ \(title)")
                .font(.headline)
                .foregroundStyle(.red)
            ForEach(Array(drops.enumerated()), id: \.offset) { _, dropped in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(dropped.eye == .right ? "Right" : "Left") eye, photo \(dropped.photoIndex + 1)")
                        .font(.caption.weight(.semibold))
                    Text(dropped.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - PD card

    private var pdCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("PD", systemImage: "ruler")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let pd = finalOutcome.pd.pd {
                    Text("\(Int(pd.rounded())) mm")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(finalOutcome.pd.requiresManualMeasurement ? .orange : .primary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if finalOutcome.pd.sourceCount > 0 {
                Text("Averaged across \(finalOutcome.pd.sourceCount) printout\(finalOutcome.pd.sourceCount == 1 ? "" : "s"). Spread \(String(format: "%.1f", finalOutcome.pd.spreadMm)) mm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Per-photo disclosure

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

    // MARK: - Save button

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = saveState.disabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if saving {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    }
                    Text(saving ? "Saving…" : saveButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(saving || !saveState.enabled)
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(.background)
    }

    private var saveButtonTitle: String {
        if finalOutcome.requiresManualReview { return "Save for manual review" }
        switch finalOutcome.overallTier {
        case .tier3DoNotDispense, .tier4MedicalConcern:
            return "Save referral & return"
        case .tier0NoGlassesNeeded:
            return tier0Decision == .noGlassesNeeded ? "Save (no glasses) & return" : "Save & return"
        default:
            return "Save & return"
        }
    }

    // MARK: - Severity helpers

    private func color(for severity: TierPresentation.Severity) -> Color {
        switch severity {
        case .info:     return .blue
        case .success:  return .green
        case .warning:  return .orange
        case .blocking: return .red
        }
    }

    private func iconName(for severity: TierPresentation.Severity) -> String {
        switch severity {
        case .info:     return "info.circle.fill"
        case .success:  return "checkmark.seal.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .blocking: return "exclamationmark.octagon.fill"
        }
    }

    private func color(for severity: ClinicalFlagInstruction.Severity) -> Color {
        switch severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .blocking: return .red
        }
    }

    private func iconName(for severity: ClinicalFlagInstruction.Severity) -> String {
        switch severity {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .blocking: return "exclamationmark.octagon.fill"
        }
    }

    // MARK: - Save

    private func save() async {
        saving = true
        refraction.apply(
            outcome: finalOutcome,
            patientNotifiedTier2: finalOutcome.overallTier == .tier2StretchWithNotification
                ? patientNotifiedTier2
                : nil,
            tier0Decision: finalOutcome.overallTier == .tier0NoGlassesNeeded
                ? tier0Decision
                : nil
        )
        await sync.save(refraction)
        saving = false
        NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
    }
}

extension Notification.Name {
    static let hicorReturnToRoot = Notification.Name("hicor.returnToRoot")
}
