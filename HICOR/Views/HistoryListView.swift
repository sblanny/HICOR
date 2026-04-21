import SwiftUI
import SwiftData

struct HistoryListView: View {
    let location: String
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var patients: [PatientRefraction] = []
    @State private var search: String = ""
    @State private var loadError: String?

    init(location: String, date: Date) {
        self.location = location
        self.date = date
    }

    init(sessionContext: SessionContext) {
        self.location = sessionContext.location
        self.date = sessionContext.date
    }

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(onBack: { dismiss() })

            VStack(spacing: 12) {
                titleBlock
                searchField
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if let loadError {
                errorBanner(loadError)
            }

            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            load()
        }
        .navigationDestination(for: PatientRefraction.self) { refraction in
            PatientDetailView(refraction: refraction)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 2) {
            Text("History")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("\(location)  ·  \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Patient #", text: $search)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            List(filtered) { patient in
                NavigationLink(value: patient) {
                    HistoryRow(patient: patient)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(patients.isEmpty ? "No patients yet today" : "No matches")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red)
    }

    private var filtered: [PatientRefraction] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return patients }
        return patients.filter { $0.patientNumber.contains(query) }
    }

    private func load() {
        let repo = PatientRefractionRepository(modelContext: modelContext)
        do {
            patients = try repo.patientsForToday(location: location, date: date)
            loadError = nil
        } catch {
            patients = []
            loadError = "Couldn't load history: \(error.localizedDescription)"
        }
    }
}

private struct HistoryRow: View {
    let patient: PatientRefraction

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Patient #\(patient.patientNumber)")
                    .font(.system(size: 20, weight: .semibold))
                Text(prescriptionSummary)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                tierBadge
                Text(patient.createdAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var prescriptionSummary: String {
        let od = eyeSummary(sph: patient.odSPH, cyl: patient.odCYL, ax: patient.odAX)
        let os = eyeSummary(sph: patient.osSPH, cyl: patient.osCYL, ax: patient.osAX)
        return "R: \(od)   L: \(os)"
    }

    private func eyeSummary(sph: Double, cyl: Double, ax: Int) -> String {
        let sphStr = formatSigned(sph)
        let cylStr = formatSigned(cyl)
        return "\(sphStr) / \(cylStr) × \(String(format: "%03d", ax))"
    }

    private func formatSigned(_ v: Double) -> String {
        let sign = v >= 0 ? "+" : "-"
        return String(format: "%@%.2f", sign, abs(v))
    }

    @ViewBuilder
    private var tierBadge: some View {
        if let raw = patient.dispensingTier, let tier = DispensingTier(rawValue: raw) {
            let presentation = TierPresentation.make(for: tier)
            Text(shortLabel(for: tier))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color(for: presentation.severity).opacity(0.2))
                .foregroundStyle(color(for: presentation.severity))
                .clipShape(Capsule())
        } else {
            EmptyView()
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
        case .info: return .gray
        case .success: return .green
        case .warning: return .orange
        case .blocking: return .red
        }
    }
}
