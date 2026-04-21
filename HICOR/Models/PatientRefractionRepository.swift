import Foundation
import SwiftData

@MainActor
final class PatientRefractionRepository {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func patientsForToday(location: String, date: Date) throws -> [PatientRefraction] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionLocation == location &&
            p.sessionDate >= start &&
            p.sessionDate < end
        }
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.patientNumber)]
        )
        return try modelContext.fetch(descriptor)
    }
}
