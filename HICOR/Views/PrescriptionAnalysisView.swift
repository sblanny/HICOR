import SwiftUI

struct PrescriptionAnalysisView: View {
    let refraction: PatientRefraction
    let results: [PrintoutResult]
    var droppedOutliers: [ConsistencyValidator.DroppedReading] = []
    let finalOutcome: PrescriptionCalculationOutcome
    /// Invoked when the operator taps "Capture additional printout."
    /// Caller pops back to PhotoCaptureView with existing printouts intact
    /// so a 3rd, 4th, or 5th printout can be added before saving. Same
    /// closure DisagreementReviewView's onAddAnother uses — the volunteer
    /// is the final clinical judge, not the algorithm. nil disables the
    /// affordance (e.g. previews / tests that don't need navigation).
    var onCaptureAdditional: (() -> Void)? = nil

    @Environment(SyncCoordinator.self) private var sync
    @State private var saving = false
    @State private var patientNotifiedTier2 = false
    @State private var tier0BlurryVision: Tier0SymptomCheck.Answer = .unanswered
    @State private var tier0Headaches: Tier0SymptomCheck.Answer = .unanswered
    @State private var tier0Squinting: Tier0SymptomCheck.Answer = .unanswered
    @State private var showHistory = false
    @State private var showAbout = false
    @State private var confirmDiscard = false

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
        VStack(spacing: 0) {
            SharedHeader(
                onShowHistory: { showHistory = true },
                onChangeLocation: { confirmDiscard = true },
                onShowAbout: { showAbout = true }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    tierBanner
                    if finalOutcome.overallTier == .tier0NoGlassesNeeded {
                        tier0SymptomSection
                    }
                    finalPrescriptionCard
                    if tierPresentation.requiresPatientNotifiedAcknowledgement {
                        tier2AcknowledgeSection
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

                    DisclosureGroup("Per-printout readings") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                                PrintoutReadingsCard(index: idx, result: result)
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
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryListView(
                    location: refraction.sessionLocation,
                    date: refraction.sessionDate
                )
            }
        }
        .alert("CLEAR Ministry", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Highlands Church Optical Refraction\nVersion 1.0")
        }
        .alert("Discard current patient?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard and Continue", role: .destructive) {
                NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
            }
        } message: {
            Text("Going back to Location setup will discard the current patient's data. This cannot be undone.")
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
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(DiopterFormatter.format(rx.sph)).frame(width: 70, alignment: .leading)
                    Text(DiopterFormatter.cylDisplayString(calculated: rx.cyl))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(DiopterFormatter.formatAxis(rx.ax))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
                    Text("\(dropped.eye == .right ? "Right" : "Left") eye, printout \(dropped.photoIndex + 1)")
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
            // Capture-additional sits above Save & return as a secondary
            // affordance: the volunteer can always opt in to more data
            // before committing, regardless of tier. Hidden once the 5-
            // printout ceiling is reached — there's no more capacity.
            if canCaptureAdditional {
                Button {
                    onCaptureAdditional?()
                } label: {
                    Text("Capture additional printout")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(saving)
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

    private var canCaptureAdditional: Bool {
        CaptureAdditionalGate.isAvailable(
            printoutCount: results.count,
            callbackProvided: onCaptureAdditional != nil
        )
    }

    private var saveButtonTitle: String {
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
        // Source of truth for the patient's session date is the system clock
        // at save time, not whatever was on SessionContext when Trip Setup
        // began. Captures crossing midnight stay correctly tagged.
        refraction.sessionDate = Date()
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
        NotificationCenter.default.post(name: .hicorReturnToPatientEntry, object: nil)
    }
}

extension Notification.Name {
    static let hicorReturnToRoot = Notification.Name("hicor.returnToRoot")
    static let hicorReturnToPatientEntry = Notification.Name("hicor.returnToPatientEntry")
}
