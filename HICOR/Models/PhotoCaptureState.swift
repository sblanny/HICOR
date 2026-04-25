import Foundation
import Observation

/// One physical autorefractor printout, captured as one or more photos.
/// Multiple photos of the same sheet feed into OCR consensus so dim or
/// faded glyphs can be rescued from a different angle. `finalized` flips
/// when the operator taps the done-with-this-printout checkmark, and no
/// further photos get added to this group — the next capture starts a
/// new `Printout`.
struct Printout: Identifiable, Equatable {
    let id: UUID
    var photos: [Data]
    var finalized: Bool

    init(id: UUID = UUID(), photos: [Data] = [], finalized: Bool = false) {
        self.id = id
        self.photos = photos
        self.finalized = finalized
    }
}

@Observable
final class PhotoCaptureState {
    /// Invariant: never empty after the first photo is captured. The last
    /// element is the "active" printout unless it's `finalized`, in which
    /// case the next capture appends a fresh unfinalized group.
    var printouts: [Printout] = [Printout()]
    var pdValue: String = ""
    var pdManualEntryRequired: Bool = false

    var totalPhotoCount: Int {
        printouts.reduce(0) { $0 + $1.photos.count }
    }

    var capturedPrintoutCount: Int {
        printouts.filter { !$0.photos.isEmpty }.count
    }

    var currentPrintoutPhotoCount: Int {
        printouts.last?.photos.count ?? 0
    }

    private var canAddToCurrentPrintout: Bool {
        guard let current = printouts.last else { return false }
        return !current.finalized && current.photos.count < Constants.maxPhotosPerPrintout
    }

    private var canStartAnotherPrintout: Bool {
        capturedPrintoutCount < Constants.maxPrintoutsAllowed
    }

    var canAddMorePhotos: Bool {
        guard let current = printouts.last else { return false }
        if current.finalized {
            return canStartAnotherPrintout
        }
        return canAddToCurrentPrintout
    }

    var canAnalyze: Bool {
        printouts.contains { !$0.photos.isEmpty }
    }

    /// True only when the operator has added ≥1 photo to the current
    /// printout and hasn't yet tapped the done-with-this-printout button.
    /// Gates visibility of the ✓ toolbar action in the capture view.
    var canFinalizeCurrentPrintout: Bool {
        guard let current = printouts.last else { return false }
        return !current.finalized && !current.photos.isEmpty
    }

    var isReadyToCommit: Bool {
        guard canAnalyze else { return false }
        if pdManualEntryRequired {
            return !pdValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    /// Flat view of every captured photo across every printout. Used by
    /// downstream code that still takes a flat `[Data]` (image storage,
    /// debug snapshots). Ordering preserves capture order.
    var allPhotosFlat: [Data] {
        printouts.flatMap(\.photos)
    }

    /// Appends to the active (last unfinalized) printout. If the last
    /// printout is finalized, starts a new printout first — callers never
    /// have to think about group management.
    func addPhoto(_ data: Data) {
        guard canAddMorePhotos else { return }
        if printouts.last?.finalized == true {
            printouts.append(Printout())
        }
        printouts[printouts.count - 1].photos.append(data)
    }

    /// Marks the active printout done. No-op if it has no photos yet
    /// (don't create an empty group the operator has to dismiss).
    func finalizeCurrentPrintout() {
        guard canFinalizeCurrentPrintout else { return }
        printouts[printouts.count - 1].finalized = true
    }

    /// Un-finalize a specific printout so new captures flow into it. Used
    /// when analyze-time consensus surfaces a cell gap that only another
    /// photo of THAT sheet can fill. Any existing active-printout work is
    /// preserved as its own group — just pushed down; the target printout
    /// becomes the active one again.
    func reactivatePrintout(id: UUID) {
        guard let idx = printouts.firstIndex(where: { $0.id == id }) else { return }
        // Make this the last element so future addPhoto targets it. Keep
        // its photos intact; just clear the finalized flag and move to tail.
        var target = printouts.remove(at: idx)
        target.finalized = false
        printouts.append(target)
    }

    func removePhoto(printoutId: UUID, photoIndex: Int) {
        guard let pIdx = printouts.firstIndex(where: { $0.id == printoutId }) else { return }
        guard printouts[pIdx].photos.indices.contains(photoIndex) else { return }
        printouts[pIdx].photos.remove(at: photoIndex)
        // If removing the last photo leaves an empty non-tail printout,
        // drop the group entirely to avoid empty slots in the UI. The tail
        // printout is allowed to be empty — it's the "next capture goes
        // here" slot.
        if printouts[pIdx].photos.isEmpty && pIdx != printouts.count - 1 {
            printouts.remove(at: pIdx)
        }
    }
}
