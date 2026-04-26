import SwiftUI

struct PatientDetailView: View {
    let refraction: PatientRefraction

    @Environment(\.dismiss) private var dismiss
    @State private var fullScreenPhotoIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    patientHeader
                    finalPrescriptionCard
                    acceptanceStatusSection
                    clinicalFlagsSection
                    pdSection
                    droppedOutliersSection
                    perPhotoReadingsSection
                    capturedPhotosSection
                    Spacer(minLength: 32)
                }
                .padding()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: Binding(
            get: { fullScreenPhotoIndex.map(IndexBox.init) },
            set: { fullScreenPhotoIndex = $0?.value }
        )) { box in
            FullScreenPhotoView(
                imageData: refraction.photoData[box.value],
                index: box.value,
                total: refraction.photoData.count,
                onDismiss: { fullScreenPhotoIndex = nil }
            )
        }
    }

    // MARK: - Patient header

    private var patientHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Patient #\(refraction.patientNumber)")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Text("\(refraction.sessionLocation) · \(refraction.sessionDate.formatted(date: .abbreviated, time: .omitted)) · \(refraction.createdAt.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Final prescription

    private var finalPrescriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Final prescription").font(.headline)
                Spacer()
                tierBadge
            }

            prescriptionRow(label: "Right (OD)",
                            sph: refraction.odSPH,
                            cyl: refraction.odCYL,
                            ax: refraction.odAX,
                            source: refraction.finalRightSource)
            prescriptionRow(label: "Left (OS)",
                            sph: refraction.osSPH,
                            cyl: refraction.osCYL,
                            ax: refraction.osAX,
                            source: refraction.finalLeftSource)

            if !refraction.matchedLensOD.isEmpty || !refraction.matchedLensOS.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !refraction.matchedLensOD.isEmpty {
                        Text("OD lens: \(refraction.matchedLensOD)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !refraction.matchedLensOS.isEmpty {
                        Text("OS lens: \(refraction.matchedLensOS)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func prescriptionRow(label: String, sph: Double, cyl: Double, ax: Int, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                Text(DiopterFormatter.format(sph)).frame(width: 70, alignment: .leading)
                Text(DiopterFormatter.format(cyl)).frame(width: 70, alignment: .leading)
                Text(DiopterFormatter.formatAxis(ax))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(.title3, design: .monospaced))
            if let source {
                Text("Source: \(formatSourceLabel(source))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let raw = refraction.dispensingTier, let tier = DispensingTier(rawValue: raw) {
            let presentation = TierPresentation.make(for: tier)
            Text(shortLabel(for: tier))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color(for: presentation.severity).opacity(0.2))
                .foregroundStyle(color(for: presentation.severity))
                .clipShape(Capsule())
        } else {
            EmptyView()
        }
    }

    // MARK: - Acceptance status

    @ViewBuilder
    private var acceptanceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if refraction.manualReviewRequired {
                statusBanner(
                    icon: "exclamationmark.octagon.fill",
                    tint: .red,
                    text: "Manual review required"
                )
            }
            if let tier2Notified = refraction.patientNotifiedTier2 {
                if tier2Notified {
                    statusBanner(
                        icon: "checkmark.seal.fill",
                        tint: .green,
                        text: "Patient was notified of the stretch (Tier 2) fit"
                    )
                } else {
                    statusBanner(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        text: "Tier 2 saved without confirmed patient notification"
                    )
                }
            }
            if let reason = refraction.noGlassesReason, !reason.isEmpty {
                statusBanner(
                    icon: "checkmark.seal",
                    tint: .blue,
                    text: "No glasses needed — patient reported: \(reason)"
                )
            }
            if refraction.consistencyWarningOverridden {
                statusBanner(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    text: "Consistency warning was overridden"
                )
            }
        }
    }

    private func statusBanner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.subheadline)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Clinical flags

    @ViewBuilder
    private var clinicalFlagsSection: some View {
        let flags = decodedClinicalFlags
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clinical flags").font(.headline)
                ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                    flagRow(ClinicalFlagInstruction.make(for: flag))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func flagRow(_ instruction: ClinicalFlagInstruction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(instruction.title, systemImage: iconName(for: instruction.severity))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color(for: instruction.severity))
            Text(instruction.body).font(.footnote)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(for: instruction.severity).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - PD

    private var pdSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("PD").font(.headline)
                Spacer()
                Text("\(Int(refraction.pd)) mm")
                    .font(.system(.title3, design: .monospaced))
            }
            Text(pdSourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var pdSourceLabel: String {
        if refraction.pdManualEntry {
            return "Manually entered"
        }
        if let source = refraction.pdSource, source == "aggregate-manual-recommended" {
            return String(format: "Averaged from printouts — manual remeasure recommended (spread %.1f mm)", refraction.pdSpread)
        }
        if refraction.pdSpread > 0 {
            return String(format: "Averaged from printouts (spread %.1f mm)", refraction.pdSpread)
        }
        return "Averaged from printouts"
    }

    // MARK: - Dropped outliers

    @ViewBuilder
    private var droppedOutliersSection: some View {
        let dropped = decodedDroppedOutliers
        if !dropped.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Dropped outliers", systemImage: "minus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                ForEach(Array(dropped.enumerated()), id: \.offset) { _, dr in
                    droppedOutlierRow(dr)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func droppedOutlierRow(_ dr: ConsistencyValidator.DroppedReading) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Printout \(dr.photoIndex + 1) — \(dr.eye == .right ? "Right (OD)" : "Left (OS)")")
                .font(.subheadline.weight(.semibold))
            Text(formatReading(dr.reading))
                .font(.system(.caption, design: .monospaced))
            Text(dr.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Per-printout readings

    @ViewBuilder
    private var perPhotoReadingsSection: some View {
        let results = decodedPrintouts
        if !results.isEmpty {
            DisclosureGroup("Per-printout readings (\(results.count))") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(results.enumerated()), id: \.offset) { idx, r in
                        perPhotoCard(index: idx, result: r)
                    }
                }
                .padding(.top, 8)
            }
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func perPhotoCard(index: Int, result: PrintoutResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Printout \(index + 1)").font(.subheadline.weight(.semibold))
                Spacer()
                Text(result.machineType == .desktop ? "Desktop" : "Handheld")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
            }
            eyeBlock(label: "R", reading: result.rightEye)
            eyeBlock(label: "L", reading: result.leftEye)
            if let pd = result.pd {
                Text("PD \(Int(pd)) mm").font(.caption2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func eyeBlock(label: String, reading: EyeReading?) -> some View {
        if let reading, !reading.readings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(reading.readings) { r in
                    Text("\(label): \(formatReading(r))")
                        .font(.system(.caption, design: .monospaced))
                        .opacity(r.lowConfidence ? 0.6 : 1.0)
                }
                if let aSPH = reading.machineAvgSPH,
                   let aCYL = reading.machineAvgCYL,
                   let aAX  = reading.machineAvgAX {
                    Text("\(label) AVG: \(DiopterFormatter.format(aSPH)) / \(DiopterFormatter.format(aCYL)) × \(aAX)°")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        } else {
            Text("\(label): —")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Captured photos

    @ViewBuilder
    private var capturedPhotosSection: some View {
        if !refraction.photoData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Captured photos (\(refraction.photoData.count))").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(refraction.photoData.enumerated()), id: \.offset) { idx, data in
                            if let ui = UIImage(data: data) {
                                Button {
                                    fullScreenPhotoIndex = idx
                                } label: {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 150)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .bottomLeading) {
                                            Text("#\(idx + 1)")
                                                .font(.caption2.weight(.bold))
                                                .padding(4)
                                                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                                                .foregroundStyle(.white)
                                                .padding(6)
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Decoding helpers

    private var decodedPrintouts: [PrintoutResult] {
        guard !refraction.rawReadingsData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([PrintoutResult].self, from: refraction.rawReadingsData)) ?? []
    }

    private var decodedClinicalFlags: [ClinicalFlag] {
        guard !refraction.clinicalFlagsJSON.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ClinicalFlag].self, from: refraction.clinicalFlagsJSON)) ?? []
    }

    private var decodedDroppedOutliers: [ConsistencyValidator.DroppedReading] {
        guard !refraction.droppedOutliersJSON.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ConsistencyValidator.DroppedReading].self, from: refraction.droppedOutliersJSON)) ?? []
    }

    // MARK: - Formatting

    private func formatReading(_ r: RawReading) -> String {
        if r.isSphOnly {
            return "\(DiopterFormatter.format(r.sph)) / — × —"
        }
        return "\(DiopterFormatter.format(r.sph)) / \(DiopterFormatter.format(r.cyl)) × \(r.ax)°"
    }

    private func formatSourceLabel(_ source: String) -> String {
        // Turn internal raw values (e.g. "machine", "recomputedViaPowerVector") into
        // a human-readable label. The full enum is PrescriptionSource but we only
        // get its rawValue here; pretty-print known values, fall back to raw.
        switch source {
        case "machine": return "Machine average"
        case "recomputedViaPowerVector": return "Recomputed via power-vector average"
        case "sphOnlyAverage": return "SPH-only average"
        default: return source
        }
    }

    private func shortLabel(for tier: DispensingTier) -> String {
        switch tier {
        case .tier0NoGlassesNeeded: return "Tier 0"
        case .tier1Normal: return "Tier 1"
        case .tier2StretchWithNotification: return "Tier 2"
        case .tier3DoNotDispense: return "Tier 3"
        case .tier4MedicalConcern: return "Tier 4"
        }
    }

    private func color(for severity: TierPresentation.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .blocking: return .red
        }
    }

    private func color(for severity: ClinicalFlagInstruction.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .blocking: return .red
        }
    }

    private func iconName(for severity: ClinicalFlagInstruction.Severity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .blocking: return "exclamationmark.octagon.fill"
        }
    }
}

private struct IndexBox: Identifiable {
    let value: Int
    var id: Int { value }
}
