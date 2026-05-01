import Foundation
import SwiftData

@MainActor
final class PatientRefractionRepository {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func patientsForToday(location: String, date: Date) throws -> [PatientRefraction] {
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionDate >= start && p.sessionDate < end
        }
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.patientNumber)]
        )
        let dayMatches = try modelContext.fetch(descriptor)
        return dayMatches.filter {
            $0.sessionLocation.trimmingCharacters(in: .whitespaces) == trimmedLocation
        }
    }

    func availableDates(forLocation location: String) throws -> [Date] {
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let descriptor = FetchDescriptor<PatientRefraction>(
            sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        let cal = Calendar.current
        var seen = Set<Date>()
        var dates: [Date] = []
        for patient in all
        where patient.sessionLocation.trimmingCharacters(in: .whitespaces) == trimmedLocation {
            let day = cal.startOfDay(for: patient.sessionDate)
            if seen.insert(day).inserted {
                dates.append(day)
            }
        }
        return dates
    }

    func patientCount(forLocation location: String, date: Date) throws -> Int {
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionDate >= start && p.sessionDate < end
        }
        let descriptor = FetchDescriptor<PatientRefraction>(predicate: predicate)
        let dayMatches = try modelContext.fetch(descriptor)
        return dayMatches.filter {
            $0.sessionLocation.trimmingCharacters(in: .whitespaces) == trimmedLocation
        }.count
    }
}
