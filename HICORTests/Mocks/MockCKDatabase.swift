import Foundation
import CloudKit
@testable import HICOR

final class MockCKDatabase: CKDatabaseProtocol {
    enum SaveBehavior {
        case echo
        case returnRecord(CKRecord)
        case throwError(Error)
    }

    var saveBehavior: SaveBehavior = .echo
    var queryRecords: [CKRecord] = []
    var queryError: Error?

    private(set) var savedRecords: [CKRecord] = []
    private(set) var queryCount = 0

    func save(_ record: CKRecord) async throws -> CKRecord {
        savedRecords.append(record)
        switch saveBehavior {
        case .echo:
            return record
        case .returnRecord(let r):
            return r
        case .throwError(let e):
            throw e
        }
    }

    func records(
        matching query: CKQuery,
        inZoneWith zoneID: CKRecordZone.ID?,
        desiredKeys: [CKRecord.FieldKey]?,
        resultsLimit: Int
    ) async throws -> (
        matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
        queryCursor: CKQueryOperation.Cursor?
    ) {
        queryCount += 1
        if let err = queryError { throw err }
        let matches = queryRecords.map { record in
            (record.recordID, Result<CKRecord, Error>.success(record))
        }
        return (matches, nil)
    }
}
