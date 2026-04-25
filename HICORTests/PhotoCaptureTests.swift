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

    func testAddPhotoAppendsToActivePrintout() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.addPhoto(Data([0x02]))
        XCTAssertEqual(state.printouts.count, 1, "Both photos belong to the same unfinalized printout")
        XCTAssertEqual(state.printouts[0].photos.count, 2)
    }

    func testFinalizeStartsNextPrintoutOnNextCapture() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.finalizeCurrentPrintout()
        state.addPhoto(Data([0x02]))

        XCTAssertEqual(state.printouts.count, 2)
        XCTAssertTrue(state.printouts[0].finalized)
        XCTAssertEqual(state.printouts[0].photos, [Data([0x01])])
        XCTAssertFalse(state.printouts[1].finalized)
        XCTAssertEqual(state.printouts[1].photos, [Data([0x02])])
    }

    func testFinalizeIsNoOpWithoutPhotos() {
        let state = PhotoCaptureState()
        state.finalizeCurrentPrintout()
        XCTAssertFalse(state.canFinalizeCurrentPrintout)
        XCTAssertEqual(state.printouts.count, 1, "Empty active printout should not be finalized")
        XCTAssertFalse(state.printouts[0].finalized)
    }

    func testCurrentPrintoutRespectsPerPrintoutMaximum() {
        let state = PhotoCaptureState()
        for byte in 0..<Constants.maxPhotosPerPrintout {
            state.addPhoto(Data([UInt8(byte)]))
        }
        XCTAssertFalse(state.canAddMorePhotos)
        state.addPhoto(Data([0xFF]))
        XCTAssertEqual(state.totalPhotoCount, Constants.maxPhotosPerPrintout, "Per-printout over-cap addPhoto is a no-op")
        XCTAssertEqual(state.printouts.count, 1)
    }

    func testFinalizedPrintoutCountRespectsMaximum() {
        let state = PhotoCaptureState()

        for printoutIndex in 0..<Constants.maxPrintoutsAllowed {
            state.addPhoto(Data([UInt8(printoutIndex)]))
            state.finalizeCurrentPrintout()
        }

        XCTAssertEqual(state.capturedPrintoutCount, Constants.maxPrintoutsAllowed)
        XCTAssertFalse(state.canAddMorePhotos)

        state.addPhoto(Data([0xFF]))
        XCTAssertEqual(state.capturedPrintoutCount, Constants.maxPrintoutsAllowed, "Over-cap printout addPhoto is a no-op")
        XCTAssertEqual(state.totalPhotoCount, Constants.maxPrintoutsAllowed)
    }

    func testRemovePhotoDropsFromSpecifiedPrintout() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.addPhoto(Data([0x02]))
        let id = state.printouts[0].id

        state.removePhoto(printoutId: id, photoIndex: 0)
        XCTAssertEqual(state.printouts[0].photos, [Data([0x02])])
    }

    func testRemovingLastPhotoFromNonTailPrintoutDropsTheGroup() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.finalizeCurrentPrintout()
        state.addPhoto(Data([0x02]))

        let firstId = state.printouts[0].id
        XCTAssertEqual(state.printouts.count, 2)

        state.removePhoto(printoutId: firstId, photoIndex: 0)
        XCTAssertEqual(state.printouts.count, 1, "Empty non-tail printout should be pruned so it doesn't linger")
        XCTAssertEqual(state.printouts[0].photos, [Data([0x02])])
    }

    func testReactivatePrintoutMovesItToTailAndUnfinalizes() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.finalizeCurrentPrintout()
        state.addPhoto(Data([0x02]))

        let firstId = state.printouts[0].id
        state.reactivatePrintout(id: firstId)

        XCTAssertEqual(state.printouts.count, 2)
        XCTAssertEqual(state.printouts.last?.id, firstId, "Reactivated printout is moved to tail so next capture adds to it")
        XCTAssertFalse(state.printouts.last?.finalized ?? true)
        XCTAssertEqual(state.printouts.last?.photos, [Data([0x01])], "Existing photos preserved through reactivation")
    }

    func testReactivatedPrintoutCanAcceptAnotherPhotoUpToPerPrintoutMaximum() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.finalizeCurrentPrintout()
        state.addPhoto(Data([0x02]))

        let firstId = state.printouts[0].id
        state.reactivatePrintout(id: firstId)
        state.addPhoto(Data([0x03]))

        XCTAssertEqual(state.printouts.last?.id, firstId)
        XCTAssertEqual(state.printouts.last?.photos.count, 2, "Reactivated printout should accept another capture")
        XCTAssertEqual(state.totalPhotoCount, 3)
    }

    func testPDRequiredBlocksCommitUntilEntered() {
        let state = PhotoCaptureState()
        state.addPhoto(Data([0x01]))
        state.pdManualEntryRequired = true

        XCTAssertTrue(state.canAnalyze)
        XCTAssertFalse(state.isReadyToCommit, "Commit blocked until PD entered")

        state.pdValue = "62"
        XCTAssertTrue(state.isReadyToCommit)
    }
}
