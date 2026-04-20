import SwiftUI
import UIKit

struct PhotoCaptureView: View {
    let patientNumber: String
    let sessionContext: SessionContext

    @State private var state = PhotoCaptureState()
    @State private var showingCamera = false
    @State private var fullScreenIndex: Int?
    @State private var showCommitBlockedAlert = false
    @State private var navigateToAnalysis = false
    #if DEBUG
    @State private var showingFixtureCapture = false
    #endif

    var body: some View {
        VStack(spacing: 20) {
            header

            addPhotoButton

            Text(counterText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            thumbnailRow

            if state.pdManualEntryRequired {
                pdWarningBanner
            }

            Spacer()

            analyzeButton
        }
        .padding()
        .navigationTitle("Patient #\(patientNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingCamera) {
            AutoDetectCaptureView(
                onImagePicked: { image in
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        state.addPhoto(data)
                    }
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenIndex.map { IdentifiedIndex(id: $0) } },
            set: { fullScreenIndex = $0?.id }
        )) { wrapper in
            FullScreenPhotoView(
                imageData: state.photos[wrapper.id],
                index: wrapper.id,
                total: state.photos.count,
                onDismiss: { fullScreenIndex = nil }
            )
        }
        .alert("Please enter the PD value before continuing",
               isPresented: $showCommitBlockedAlert) {
            Button("OK", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToAnalysis) {
            AnalysisPlaceholderView(
                patientNumber: patientNumber,
                sessionContext: sessionContext,
                photos: state.photos,
                pd: Double(state.pdValue) ?? 0,
                pdManualEntry: state.pdManualEntryRequired
            )
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
            Text(sessionContext.date, style: .date)
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
                Text("Add Photo")
                    .font(.headline)
            }
            .frame(width: 140, height: 140)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(.tint, lineWidth: 2))
        }
        .disabled(!state.canAddMorePhotos)
    }

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(state.photos.enumerated()), id: \.offset) { idx, data in
                    thumbnail(data: data, index: idx)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 96)
    }

    private func thumbnail(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { fullScreenIndex = index }
            }
            Button {
                state.removePhoto(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.title3)
            }
            .offset(x: 6, y: -6)
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
        let count = state.photos.count
        let min = Constants.minPhotosRequired
        let max = Constants.maxPhotosAllowed
        if count < min {
            return "\(count) of \(min) minimum"
        }
        if count < max {
            let remaining = max - count
            return "\(count) photo\(count == 1 ? "" : "s") captured (add up to \(remaining) more)"
        }
        return "\(count) photos (maximum)"
    }

    private var analyzeButtonLabel: String {
        let count = state.photos.count
        return "Analyze \(count) Photo\(count == 1 ? "" : "s")"
    }
}

private struct IdentifiedIndex: Identifiable {
    var id: Int
}
