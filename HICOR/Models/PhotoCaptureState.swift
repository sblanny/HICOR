import Foundation
import Observation

@Observable
final class PhotoCaptureState {
    var photos: [Data] = []
    var pdValue: String = ""
    var pdManualEntryRequired: Bool = false

    var canAddMorePhotos: Bool {
        photos.count < 1
    }

    var canAnalyze: Bool {
        photos.count == 1
    }

    var isReadyToCommit: Bool {
        guard canAnalyze else { return false }
        if pdManualEntryRequired {
            return !pdValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    func addPhoto(_ data: Data) {
        guard canAddMorePhotos else { return }
        photos.append(data)
    }

    func removePhoto(at index: Int) {
        guard photos.indices.contains(index) else { return }
        photos.remove(at: index)
    }
}
