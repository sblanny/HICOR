import Foundation
import SwiftData

@ModelActor
actor PersistenceService {
    func insert(_ refraction: PatientRefraction) throws {
        modelContext.insert(refraction)
        try modelContext.save()
    }

    func fetchToday() throws -> [PatientRefraction] {
        try fetch(for: Date())
    }

    func fetch(for date: Date) throws -> [PatientRefraction] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = #Predicate<PatientRefraction> { p in
            p.sessionDate >= start && p.sessionDate < end
        }
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.patientNumber)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(byID id: UUID) throws -> PatientRefraction? {
        let predicate = #Predicate<PatientRefraction> { $0.id == id }
        let descriptor = FetchDescriptor<PatientRefraction>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func fetchUnsynced() throws -> [PatientRefraction] {
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: #Predicate { $0.syncedToCloud == false }
        )
        return try modelContext.fetch(descriptor)
    }

    func markSynced(id: UUID, cloudKitRecordID: String) throws {
        let predicate = #Predicate<PatientRefraction> { $0.id == id }
        let descriptor = FetchDescriptor<PatientRefraction>(predicate: predicate)
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.cloudKitRecordID = cloudKitRecordID
        record.syncedToCloud = true
        try modelContext.save()
    }

    func save() throws {
        try modelContext.save()
    }
}
