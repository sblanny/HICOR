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
        capturedPrintoutCount >= Constants.minPrintoutsRequired
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

    /// Appends to a specific printout without changing its position in the
    /// list or its finalized flag. Used by per-row "Capture more" so a
    /// finalized earlier printout can grow another sample without becoming
    /// the active one (which would also re-number every later printout).
    func addPhoto(_ data: Data, toPrintoutId id: UUID) {
        guard let idx = printouts.firstIndex(where: { $0.id == id }) else { return }
        guard printouts[idx].photos.count < Constants.maxPhotosPerPrintout else { return }
        printouts[idx].photos.append(data)
    }

    /// Removes the printout entirely (all its photos). Used by the per-row
    /// Remove button and by the "× tap on the last remaining photo" path,
    /// both gated by a confirmation dialog at the view layer. Restores the
    /// "never empty" invariant if the last printout is the one being removed.
    func removePrintout(id: UUID) {
        printouts.removeAll { $0.id == id }
        if printouts.isEmpty {
            printouts = [Printout()]
        }
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
        // Drop below the consensus floor → printout is no longer finalized.
        // The view will hide its ✓ and the printout becomes ineligible for
        // analysis until another capture brings it back to the floor.
        if printouts[pIdx].photos.count < Constants.minPhotosPerPrintout {
            printouts[pIdx].finalized = false
        }
        // Safety net: if removing the last photo leaves an empty non-tail
        // printout, drop the group. The view layer should now intercept
        // "× tap on last photo" and route through removePrintout(id:) after
        // a confirmation dialog, so this branch is rarely exercised.
        if printouts[pIdx].photos.isEmpty && pIdx != printouts.count - 1 {
            printouts.remove(at: pIdx)
        }
    }
}
