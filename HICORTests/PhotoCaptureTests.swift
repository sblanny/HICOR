import XCTest
@testable import HICOR

final class PhotoCaptureTests: XCTestCase {
    func testCannotAnalyzeWithFewerThanTwoPhotos() {
        let state = PhotoCaptureState()
        XCTAssertFalse(state.canAnalyze)

        state.addPhoto(Data([0x01]))
        XCTAssertFalse(state.canAnalyze)

        state.addPhoto(Data([0x02]))
        XCTAssertTrue(state.canAnalyze)
    }

    func testCanAddUpToFivePhotos() {
        let state = PhotoCaptureState()
        for i in 0..<6 {
            state.addPhoto(Data([UInt8(i)]))
        }
        XCTAssertEqual(state.photos.count, Constants.maxPhotosAllowed)
        XCTAssertFalse(state.canAddMorePhotos)
    }

    func testRemovePhotoReducesCount() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.addPhoto(Data([0x02]))
        state.addPhoto(Data([0x03]))

        state.removePhoto(at: 1)

        XCTAssertEqual(state.photos.count, 2)
        XCTAssertEqual(state.photos[0], Data([0x01]))
        XCTAssertEqual(state.photos[1], Data([0x03]))
    }

    func testPDRequiredBlocksAnalyzeUntilEntered() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.addPhoto(Data([0x02]))
        state.pdManualEntryRequired = true

        XCTAssertTrue(state.canAnalyze,
                      "Button enabled so user can tap it — blocker is on commit")
        XCTAssertFalse(state.isReadyToCommit,
                       "Commit blocked until PD entered")

        state.pdValue = "62"
        XCTAssertTrue(state.isReadyToCommit)
    }
}
