import XCTest
@testable import HICOR

final class PhotoCaptureTests: XCTestCase {
    func testCannotAnalyzeWithZeroPhotos() {
        let state = PhotoCaptureState()
        XCTAssertFalse(state.canAnalyze)
    }

    func testCanAnalyzeWithOnePhoto() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        XCTAssertTrue(state.canAnalyze)
    }

    func testCannotAddMoreThanOnePhoto() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        XCTAssertFalse(state.canAddMorePhotos)

        state.addPhoto(Data([0x02]))
        XCTAssertEqual(state.photos.count, 1, "Second addPhoto must be a no-op")
    }

    func testRemovePhotoReducesCount() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        XCTAssertEqual(state.photos.count, 1)

        state.removePhoto(at: 0)
        XCTAssertEqual(state.photos.count, 0)
        XCTAssertTrue(state.canAddMorePhotos)
    }

    func testPDRequiredBlocksCommitUntilEntered() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.pdManualEntryRequired = true

        XCTAssertTrue(state.canAnalyze,
                      "Button enabled so user can tap it — blocker is on commit")
        XCTAssertFalse(state.isReadyToCommit,
                       "Commit blocked until PD entered")

        state.pdValue = "62"
        XCTAssertTrue(state.isReadyToCommit)
    }
}
