import Foundation
import SwiftData

final class PersistenceService {
    static let shared: PersistenceService = {
        let schema = Schema([PatientRefraction.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return PersistenceService(container: container)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }()

    let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
    }

    func insert(_ refraction: PatientRefraction) {
        context.insert(refraction)
        try? context.save()
    }

    func fetchToday() -> [PatientRefraction] {
        return fetch(for: Date())
    }

    func fetch(for date: Date) -> [PatientRefraction] {
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
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetch(byID id: UUID) -> PatientRefraction? {
        let predicate = #Predicate<PatientRefraction> { $0.id == id }
        let descriptor = FetchDescriptor<PatientRefraction>(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }

    func fetchUnsynced() -> [PatientRefraction] {
        let descriptor = FetchDescriptor<PatientRefraction>(
            predicate: #Predicate { $0.syncedToCloud == false }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func save() throws {
        try context.save()
    }
}
