import SwiftUI
import UIKit

struct PhotoCaptureView: View {
    let patientNumber: String
    let sessionContext: SessionContext

    @Environment(\.dismiss) private var dismiss

    @State private var state = PhotoCaptureState()
    @State private var showingCamera = false
    @State private var captureMoreTargetPrintoutId: UUID?
    @State private var pendingRemovePrintoutId: UUID?
    @State private var pendingRemoveLastPhotoPrintoutId: UUID?
    @State private var fullScreenFlatIndex: Int?
    @State private var showCommitBlockedAlert = false
    @State private var navigateToAnalysis = false
    @State private var captureRejectionMessage: String?
    @State private var showHistory = false
    @State private var showAbout = false
    @State private var confirmDiscard = false
    #if DEBUG
    @State private var showingFixtureCapture = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(
                onBack: { dismiss() },
                onShowHistory: { showHistory = true },
                onChangeLocation: { changeLocationTapped() },
                onShowAbout: { showAbout = true }
            )
            VStack(spacing: 20) {
                header

                addPhotoButton

                Text(counterText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                printoutList

                if state.canFinalizeCurrentPrintout {
                    finalizeButton
                }

                if state.pdManualEntryRequired {
                    pdWarningBanner
                }

                Spacer()

                analyzeButton
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingCamera) {
            DocumentScanView(
                onImagesPicked: { images in
                    showingCamera = false
                    saveCapturedImages(images)
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { captureMoreTargetPrintoutId.map { IdentifiedUUID(id: $0) } },
            set: { captureMoreTargetPrintoutId = $0?.id }
        )) { wrapper in
            DocumentScanView(
                onImagesPicked: { images in
                    let id = wrapper.id
                    captureMoreTargetPrintoutId = nil
                    saveCapturedImages(images, toPrintoutId: id)
                },
                onCancel: { captureMoreTargetPrintoutId = nil }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog(
            removePrintoutDialogTitle,
            isPresented: Binding(
                get: { pendingRemovePrintoutId != nil },
                set: { if !$0 { pendingRemovePrintoutId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let id = pendingRemovePrintoutId {
                    state.removePrintout(id: id)
                }
                pendingRemovePrintoutId = nil
            }
            Button("Cancel", role: .cancel) { pendingRemovePrintoutId = nil }
        }
        .confirmationDialog(
            "Remove this printout entirely?",
            isPresented: Binding(
                get: { pendingRemoveLastPhotoPrintoutId != nil },
                set: { if !$0 { pendingRemoveLastPhotoPrintoutId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let id = pendingRemoveLastPhotoPrintoutId {
                    state.removePrintout(id: id)
                }
                pendingRemoveLastPhotoPrintoutId = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoveLastPhotoPrintoutId = nil }
        }
        .alert("Could not save photo",
               isPresented: Binding(
                get: { captureRejectionMessage != nil },
                set: { if !$0 { captureRejectionMessage = nil } }
               )) {
            Button("OK", role: .cancel) { captureRejectionMessage = nil }
        } message: {
            Text(captureRejectionMessage ?? "")
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenFlatIndex.map { IdentifiedIndex(id: $0) } },
            set: { fullScreenFlatIndex = $0?.id }
        )) { wrapper in
            let flat = state.allPhotosFlat
            FullScreenPhotoView(
                imageData: flat[wrapper.id],
                index: wrapper.id,
                total: flat.count,
                onDismiss: { fullScreenFlatIndex = nil }
            )
        }
        .alert("Please enter the PD value before continuing",
               isPresented: $showCommitBlockedAlert) {
            Button("OK", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToAnalysis) {
            // Filter to non-empty printouts and retain the IDs so the
            // "Add photo to Printout N" alert can reactivate the right
            // group on return. Index into the filtered list == display
            // number − 1, which is what AnalysisPlaceholderView uses.
            let nonEmpty = state.printouts.filter { !$0.photos.isEmpty }
            AnalysisPlaceholderView(
                patientNumber: patientNumber,
                sessionContext: sessionContext,
                printouts: nonEmpty.map(\.photos),
                pd: Double(state.pdValue) ?? 0,
                pdManualEntry: state.pdManualEntryRequired,
                onReactivatePrintout: { idx in
                    guard nonEmpty.indices.contains(idx) else { return }
                    state.reactivatePrintout(id: nonEmpty[idx].id)
                },
                onReturnToCapture: {
                    // Closure capture mutates this view's state directly.
                    // SwiftUI pops AnalysisPlaceholderView (and Disagreement
                    // ReviewView above it) when the binding turns false.
                    // PhotoCaptureState is preserved across the round trip,
                    // so the operator's existing printouts are intact when
                    // they land back here.
                    navigateToAnalysis = false
                }
            )
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryListView(sessionContext: sessionContext)
            }
        }
        .alert("CLEAR Ministry", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Highlands Church Optical Refraction\nVersion 1.0")
        }
        .alert("Discard current patient?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) {}
            Button("Discard and Continue", role: .destructive) { postReturnToRoot() }
        } message: {
            Text("Going back to Location/Date setup will discard the current patient's data. This cannot be undone.")
        }
        #if DEBUG
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Toggle("DEBUG: Simulate PD not found", isOn: Binding(
                    get: { state.pdManualEntryRequired },
                    set: { state.pdManualEntryRequired = $0 }
                ))
                Button("DEBUG: Capture fixture") {
                    showingFixtureCapture = true
                }
            }
            .font(.caption)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingFixtureCapture) {
            FixtureCaptureView()
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(sessionContext.location)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Date(), style: .date)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var addPhotoButton: some View {
        Button {
            showingCamera = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36))
                Text(addPhotoButtonLabel)
                    .font(.headline)
            }
            .frame(width: 140, height: 140)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.tint, lineWidth: 2))
        }
        .disabled(!state.canAddMorePhotos)
    }

    /// Label changes based on state: "Add Photo" for the first capture of
    /// a printout, "+ Photo" once the printout has photos, "Next Printout"
    /// after the operator marked the current printout done.
    private var addPhotoButtonLabel: String {
        guard let current = state.printouts.last else { return "Add Photo" }
        if current.finalized {
            return state.capturedPrintoutCount < Constants.maxPrintoutsAllowed ? "Next Printout" : "Printouts Full"
        }
        if current.photos.count >= Constants.maxPhotosPerPrintout {
            return "Printout Full"
        }
        return current.photos.isEmpty ? "Add Photo" : "+ Photo"
    }

    private var printoutList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(state.printouts.enumerated()), id: \.element.id) { idx, printout in
                    if !printout.photos.isEmpty {
                        printoutRow(printout: printout, displayNumber: idx + 1)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func printoutRow(printout: Printout, displayNumber: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Text("Printout \(displayNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if printout.finalized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .accessibilityLabel("Printout \(displayNumber) finalized")
                }
            }

            HStack(spacing: 8) {
                ForEach(Array(printout.photos.enumerated()), id: \.offset) { photoIdx, data in
                    printoutThumbnail(
                        data: data,
                        printoutId: printout.id,
                        photoIndex: photoIdx,
                        photoCount: printout.photos.count,
                        flatIndex: flatIndex(forPrintoutId: printout.id, photoIndex: photoIdx)
                    )
                }
            }

            if printout.photos.count < Constants.maxPhotosPerPrintout {
                Button {
                    captureMoreTargetPrintoutId = printout.id
                } label: {
                    Label("Capture more", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel("Capture more photos for Printout \(displayNumber)")
            }

            Spacer(minLength: 0)

            Button("Remove", role: .destructive) {
                pendingRemovePrintoutId = printout.id
            }
            .font(.caption.weight(.semibold))
            .accessibilityLabel("Remove Printout \(displayNumber)")
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if !printout.finalized {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .offset(x: -8)
            }
        }
    }

    private func printoutThumbnail(data: Data, printoutId: UUID, photoIndex: Int, photoCount: Int, flatIndex: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { fullScreenFlatIndex = flatIndex }
            }
            Button {
                if photoCount <= 1 {
                    // Removing the sole photo is structurally identical to
                    // removing the printout — surface the destructive intent
                    // so the operator can't drop a whole sheet by tapping ×.
                    pendingRemoveLastPhotoPrintoutId = printoutId
                } else {
                    state.removePhoto(printoutId: printoutId, photoIndex: photoIndex)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.subheadline)
            }
            .offset(x: 4, y: -4)
        }
    }

    /// Map a (printoutId, photoIndex) back to its position in the flat
    /// list used by FullScreenPhotoView. Cheap — we'd expect <5 printouts
    /// with only a few photos each.
    private func flatIndex(forPrintoutId id: UUID, photoIndex: Int) -> Int {
        var offset = 0
        for printout in state.printouts {
            if printout.id == id { return offset + photoIndex }
            offset += printout.photos.count
        }
        return 0
    }

    private var finalizeButton: some View {
        Button {
            state.finalizeCurrentPrintout()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Done with this printout")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
    }

    private var pdWarningBanner: some View {
        VStack(spacing: 8) {
            Text("⚠️ PD not found. Please measure PD manually and enter it below.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            TextField("PD in mm", text: Binding(
                get: { state.pdValue },
                set: { state.pdValue = $0 }
            ))
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var analyzeButton: some View {
        Button {
            if !state.isReadyToCommit {
                showCommitBlockedAlert = true
                return
            }
            // Implicit finalize on Analyze — operator doesn't need to tap
            // the checkmark for the last printout, just hit Analyze.
            state.finalizeCurrentPrintout()
            navigateToAnalysis = true
        } label: {
            Text(analyzeButtonLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!state.canAnalyze)
    }

    private var counterText: String {
        let printoutCount = state.capturedPrintoutCount
        guard printoutCount > 0 else {
            return "No printouts yet"
        }
        let maxPrintouts = Constants.maxPrintoutsAllowed
        let maxPhotos = Constants.maxPhotosPerPrintout
        guard let current = state.printouts.last else {
            return "\(printoutCount) of \(maxPrintouts) printouts captured"
        }
        if current.finalized {
            if printoutCount < maxPrintouts {
                return "\(printoutCount) of \(maxPrintouts) printouts captured. Ready for Printout \(printoutCount + 1)."
            }
            return "\(printoutCount) of \(maxPrintouts) printouts captured."
        }
        return "Printout \(printoutCount) has \(current.photos.count) of \(maxPhotos) photos."
    }

    private var analyzeButtonLabel: String {
        let count = state.capturedPrintoutCount
        return "Analyze \(count) Printout\(count == 1 ? "" : "s")"
    }

    private func changeLocationTapped() {
        let empty = state.allPhotosFlat.isEmpty &&
                    state.pdValue.trimmingCharacters(in: .whitespaces).isEmpty
        if empty {
            postReturnToRoot()
        } else {
            confirmDiscard = true
        }
    }

    private func postReturnToRoot() {
        NotificationCenter.default.post(name: .hicorReturnToRoot, object: nil)
    }

    @MainActor
    private func saveCapturedImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        // All pages from one scanner session belong to the same physical
        // printout — VisionKit's multi-page UI is how the operator signals
        // "these are captures of the SAME sheet." Auto-finalize when we
        // come back so the next Add Photo starts a fresh printout; the
        // operator never has to think about group boundaries.
        var added = 0
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            state.addPhoto(data)
            added += 1
        }
        if added == 0 {
            captureRejectionMessage = "Could not process the captured photos. Please try again."
            return
        }
        state.finalizeCurrentPrintout()
    }

    @MainActor
    private func saveCapturedImages(_ images: [UIImage], toPrintoutId id: UUID) {
        guard !images.isEmpty else { return }
        var added = 0
        for image in images {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            state.addPhoto(data, toPrintoutId: id)
            added += 1
        }
        if added == 0 {
            captureRejectionMessage = "Could not process the captured photos. Please try again."
            return
        }
        // Mirror the top-button auto-finalize: if the printout now meets
        // the consensus floor, mark it finalized so the ✓ matches the
        // sample count without forcing the operator to manage group state.
        if let idx = state.printouts.firstIndex(where: { $0.id == id }),
           state.printouts[idx].photos.count >= Constants.minPhotosPerPrintout {
            state.printouts[idx].finalized = true
        }
    }

    private var removePrintoutDialogTitle: String {
        guard let id = pendingRemovePrintoutId,
              let idx = state.printouts.firstIndex(where: { $0.id == id }) else {
            return "Remove printout?"
        }
        return "Remove all photos in Printout \(idx + 1)?"
    }
}

private struct IdentifiedIndex: Identifiable {
    var id: Int
}

private struct IdentifiedUUID: Identifiable {
    var id: UUID
}
