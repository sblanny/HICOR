import SwiftUI
import SwiftData

struct HistoryListView: View {
    let location: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date
    @State private var patients: [PatientRefraction] = []
    @State private var availableDates: [Date] = []
    @State private var patientCounts: [Date: Int] = [:]
    @State private var showDatePicker: Bool = false
    @State private var search: String = ""
    @State private var loadError: String?
    @State private var pendingDelete: PatientRefraction?

    init(location: String, date: Date) {
        self.location = location
        _selectedDate = State(initialValue: date)
    }

    init(sessionContext: SessionContext) {
        self.location = sessionContext.location
        _selectedDate = State(initialValue: Date())
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
            #if DEBUG
            debugDumpAllRecords()
            #endif
            loadDateOptions()
            loadPatients()
        }
        .navigationDestination(for: PatientRefraction.self) { refraction in
            PatientDetailView(refraction: refraction)
        }
        .sheet(isPresented: $showDatePicker) {
            HistoryDatePicker(
                location: location,
                currentDate: selectedDate,
                availableDates: availableDates,
                patientCounts: patientCounts,
                onSelect: { newDate in
                    selectedDate = newDate
                    loadPatients()
                }
            )
        }
    }

    private var titleBlock: some View {
        Button {
            showDatePicker = true
        } label: {
            VStack(spacing: 2) {
                Text("History")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("\(location)  ·  \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = patient
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .listStyle(.plain)
            .confirmationDialog(
                "Delete this record?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { patient in
                Button("Delete Patient #\(patient.patientNumber)", role: .destructive) {
                    deletePatient(patient)
                }
                Button("Cancel", role: .cancel) {}
            } message: { patient in
                Text("This permanently removes Patient #\(patient.patientNumber) from this device. This cannot be undone.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyMessage: String {
        if !patients.isEmpty {
            return "No matches"
        }
        return Calendar.current.isDateInToday(selectedDate)
            ? "No patients yet today"
            : "No patients on this day"
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

    private func deletePatient(_ patient: PatientRefraction) {
        let repo = PatientRefractionRepository(modelContext: modelContext)
        do {
            try repo.delete(patient)
            loadPatients()
            loadDateOptions()
            loadError = nil
        } catch {
            loadError = "Couldn't delete: \(error.localizedDescription)"
        }
    }

    private func loadPatients() {
        let repo = PatientRefractionRepository(modelContext: modelContext)
        do {
            patients = try repo.patientsForToday(location: location, date: selectedDate)
            loadError = nil
        } catch {
            patients = []
            loadError = "Couldn't load history: \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private func debugDumpAllRecords() {
        let descriptor = FetchDescriptor<PatientRefraction>(
            sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]
        )
        do {
            let all = try modelContext.fetch(descriptor)
            print("🔍 [HistoryListView DEBUG] current location filter: \"\(location)\"")
            print("🔍 [HistoryListView DEBUG] total PatientRefraction records in SwiftData: \(all.count)")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            for p in all {
                print("🔍   #\(p.patientNumber)  sessionDate=\(formatter.string(from: p.sessionDate))  sessionLocation=\"\(p.sessionLocation)\"")
            }
            let cal = Calendar.current
            var byDay: [Date: [String: Int]] = [:]
            for p in all {
                let day = cal.startOfDay(for: p.sessionDate)
                byDay[day, default: [:]][p.sessionLocation, default: 0] += 1
            }
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            print("🔍 [HistoryListView DEBUG] unique days (by sessionDate startOfDay), counts per location:")
            for day in byDay.keys.sorted(by: >) {
                let perLocation = byDay[day]!
                    .map { "\"\($0.key)\"=\($0.value)" }
                    .sorted()
                    .joined(separator: ", ")
                print("🔍   \(dayFormatter.string(from: day)): \(perLocation)")
            }
        } catch {
            print("🔍 [HistoryListView DEBUG] fetch failed: \(error)")
        }
    }
    #endif

    private func loadDateOptions() {
        let repo = PatientRefractionRepository(modelContext: modelContext)
        let dates: [Date]
        do {
            dates = try repo.availableDates(forLocation: location)
        } catch {
            #if DEBUG
            print("📅 [loadDateOptions] availableDates failed: \(error)")
            #endif
            availableDates = [Calendar.current.startOfDay(for: Date())]
            patientCounts = [:]
            return
        }
        let today = Calendar.current.startOfDay(for: Date())
        var merged = dates
        if !merged.contains(today) {
            merged.insert(today, at: 0)
        }
        availableDates = merged
        #if DEBUG
        print("📅 [loadDateOptions] availableDates set to (\(merged.count)): \(merged)")
        #endif

        var counts: [Date: Int] = [:]
        for day in merged {
            do {
                counts[day] = try repo.patientCount(forLocation: location, date: day)
            } catch {
                #if DEBUG
                print("📅 [loadDateOptions] patientCount failed for \(day): \(error)")
                #endif
                counts[day] = 0
            }
        }
        patientCounts = counts
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
        let sphStr = DiopterFormatter.format(sph)
        let cylStr = DiopterFormatter.format(cyl)
        return "\(sphStr) / \(cylStr) × \(String(format: "%03d", ax))"
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
