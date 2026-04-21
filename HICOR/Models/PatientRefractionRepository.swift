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

    func availableDates(forLocation location: String) throws -> [Date] {
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionLocation == location
        }
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        let cal = Calendar.current
        var seen = Set<Date>()
        var dates: [Date] = []
        for patient in all {
            let day = cal.startOfDay(for: patient.sessionDate)
            if seen.insert(day).inserted {
                dates.append(day)
            }
        }
        return dates
    }

    func patientCount(forLocation location: String, date: Date) throws -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionLocation == location &&
            p.sessionDate >= start &&
            p.sessionDate < end
        }
        let descriptor = FetchDescriptor<PatientRefraction>(predicate: predicate)
        return try modelContext.fetchCount(descriptor)
    }
}
