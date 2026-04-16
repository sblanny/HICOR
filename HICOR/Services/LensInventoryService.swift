import Foundation
import Combine

final class LensInventoryService: ObservableObject {
    static let shared = LensInventoryService()

    @Published private(set) var inventory: LensInventory

    private let documentsDirectory: URL
    private let overrideFilename = "LensInventory.json"

    init(documentsDirectory: URL? = nil) {
        self.documentsDirectory = documentsDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.inventory = LensInventory(
            version: "0.0",
            lastUpdated: Date(),
            supportedCylinders: [],
            lenses: []
        )
    }

    func load() {
        let overrideURL = documentsDirectory.appendingPathComponent(overrideFilename)
        if let data = try? Data(contentsOf: overrideURL),
           let inv = try? Self.decoder().decode(LensInventory.self, from: data) {
            self.inventory = inv
            return
        }
        if let bundleURL = Bundle.main.url(forResource: "DefaultInventory", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let inv = try? Self.decoder().decode(LensInventory.self, from: data) {
            self.inventory = inv
            return
        }
    }

    var availableLenses: [LensOption] {
        inventory.lenses.filter { $0.available }
    }

    func closestLens(toSPH sph: Double, toCYL cyl: Double) -> LensOption? {
        return nil
    }

    func markUnavailable(sph: Double, cyl: Double) {
        setAvailability(sph: sph, cyl: cyl, available: false)
    }

    func markAvailable(sph: Double, cyl: Double) {
        setAvailability(sph: sph, cyl: cyl, available: true)
    }

    private func setAvailability(sph: Double, cyl: Double, available: Bool) {
        guard let idx = inventory.lenses.firstIndex(where: { $0.sph == sph && $0.cyl == cyl }) else { return }
        inventory.lenses[idx].available = available
        inventory.lastUpdated = Date()
    }

    func saveInventory() {
        let overrideURL = documentsDirectory.appendingPathComponent(overrideFilename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(inventory) {
            try? data.write(to: overrideURL, options: .atomic)
        }
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
