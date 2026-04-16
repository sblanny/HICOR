import XCTest
@testable import HICOR

final class LensInventoryServiceTests: XCTestCase {
    var tempDir: URL!
    var service: LensInventoryService!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = LensInventoryService(documentsDirectory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLoadFallsBackToBundleAndReturns245Lenses() {
        service.load()
        XCTAssertEqual(service.inventory.lenses.count, 245)
    }

    func testAvailableLensesFiltersOutUnavailable() {
        service.load()
        let total = service.inventory.lenses.count
        service.markUnavailable(sph: 1.50, cyl: -0.50)
        XCTAssertEqual(service.availableLenses.count, total - 1)
    }

    func testMarkUnavailableThenAvailableRestores() {
        service.load()
        service.markUnavailable(sph: 1.50, cyl: -0.50)
        XCTAssertFalse(service.inventory.lenses.first { $0.sph == 1.50 && $0.cyl == -0.50 }!.available)
        service.markAvailable(sph: 1.50, cyl: -0.50)
        XCTAssertTrue(service.inventory.lenses.first { $0.sph == 1.50 && $0.cyl == -0.50 }!.available)
    }

    func testSaveInventoryWritesToDocumentsDirectory() throws {
        service.load()
        service.markUnavailable(sph: 0.00, cyl: 0.00)
        service.saveInventory()
        let overrideURL = tempDir.appendingPathComponent("LensInventory.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: overrideURL.path))

        let svc2 = LensInventoryService(documentsDirectory: tempDir)
        svc2.load()
        XCTAssertFalse(svc2.inventory.lenses.first { $0.sph == 0.00 && $0.cyl == 0.00 }!.available)
    }

    func testClosestLensReturnsNilInPhase1() {
        service.load()
        XCTAssertNil(service.closestLens(toSPH: 1.25, toCYL: -0.25))
    }
}
