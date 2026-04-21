import XCTest
import SwiftData
@testable import HICOR

@MainActor
final class PatientRefractionRepositoryTests: XCTestCase {
    var container: ModelContainer!
    var repo: PatientRefractionRepository!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: PatientRefraction.self, configurations: config)
        repo = PatientRefractionRepository(modelContext: ModelContext(container))
    }

    override func tearDown() {
        repo = nil
        container = nil
        super.tearDown()
    }

    private func insert(_ p: PatientRefraction) throws {
        repo.modelContext.insert(p)
        try repo.modelContext.save()
    }

    func testReturnsPatientsMatchingLocationAndDate() throws {
        let today = Date()
        let p = PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "San Quintin")
        try insert(p)

        let results = try repo.patientsForToday(location: "San Quintin", date: today)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "001")
    }

    func testExcludesPatientsFromOtherLocations() throws {
        let today = Date()
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "San Quintin"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: today, sessionLocation: "Ensenada"))

        let results = try repo.patientsForToday(location: "San Quintin", date: today)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "001")
    }

    func testExcludesPatientsFromOtherDates() throws {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        try insert(PatientRefraction(patientNumber: "001", sessionDate: yesterday, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "003", sessionDate: tomorrow, sessionLocation: "Loc"))

        let results = try repo.patientsForToday(location: "Loc", date: today)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.patientNumber, "002")
    }

    func testOrdersByPatientNumberAscending() throws {
        let today = Date()
        try insert(PatientRefraction(patientNumber: "010", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "003", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "007", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "Loc"))

        let results = try repo.patientsForToday(location: "Loc", date: today)
        XCTAssertEqual(results.map(\.patientNumber), ["001", "003", "007", "010"])
    }

    func testReturnsEmptyArrayWhenNoMatches() throws {
        let today = Date()
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "Other"))

        let results = try repo.patientsForToday(location: "Loc", date: today)
        XCTAssertTrue(results.isEmpty)
    }

    func testDateRangeIncludesFullDayBoundaries() throws {
        let today = Date()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        let endOfTodayMinusOne = cal.date(byAdding: .second, value: 86_399, to: startOfToday)!

        try insert(PatientRefraction(patientNumber: "100", sessionDate: startOfToday, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "200", sessionDate: endOfTodayMinusOne, sessionLocation: "Loc"))

        let results = try repo.patientsForToday(location: "Loc", date: today)
        XCTAssertEqual(results.count, 2)
    }

    // MARK: - availableDates

    func testAvailableDatesReturnsDistinctDays() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let midMorning = cal.date(byAdding: .hour, value: 9, to: today)!
        let midAfternoon = cal.date(byAdding: .hour, value: 15, to: today)!

        try insert(PatientRefraction(patientNumber: "001", sessionDate: midMorning, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: midAfternoon, sessionLocation: "Loc"))

        let dates = try repo.availableDates(forLocation: "Loc")
        XCTAssertEqual(dates.count, 1)
        XCTAssertEqual(dates.first, today)
    }

    func testAvailableDatesOrderedMostRecentFirst() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: today)!

        try insert(PatientRefraction(patientNumber: "003", sessionDate: twoDaysAgo, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: yesterday, sessionLocation: "Loc"))

        let dates = try repo.availableDates(forLocation: "Loc")
        XCTAssertEqual(dates, [today, yesterday, twoDaysAgo])
    }

    func testAvailableDatesFiltersByLocation() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "San Quintin"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: yesterday, sessionLocation: "Ensenada"))

        let dates = try repo.availableDates(forLocation: "San Quintin")
        XCTAssertEqual(dates, [today])
    }

    // MARK: - patientCount

    func testPatientCountForLocationAndDate() throws {
        let today = Date()
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "002", sessionDate: today, sessionLocation: "Loc"))
        try insert(PatientRefraction(patientNumber: "003", sessionDate: today, sessionLocation: "Other"))

        let count = try repo.patientCount(forLocation: "Loc", date: today)
        XCTAssertEqual(count, 2)
    }

    func testPatientCountReturnsZeroForEmptyDay() throws {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        try insert(PatientRefraction(patientNumber: "001", sessionDate: today, sessionLocation: "Loc"))

        let count = try repo.patientCount(forLocation: "Loc", date: yesterday)
        XCTAssertEqual(count, 0)
    }
}
