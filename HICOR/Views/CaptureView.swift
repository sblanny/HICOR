import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera capture view with torch toggle and a dashed framing
/// overlay matching the GRK-6000 printout's ~3:4 portrait aspect ratio
/// (thermal slip held portrait so both R and L sections fit vertically).
/// Calls `onImagePicked` with the captured UIImage, or `onCancel` when the
/// user backs out.
struct CaptureView: View {

    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var model = CaptureModel()

    var body: some View {
        ZStack {
            CapturePreview(model: model).ignoresSafeArea()

            // Framing guide — 3:4 portrait, fits the vertical slip.
            GeometryReader { geo in
                let maxHeight = geo.size.height * 0.8
                let maxWidth = geo.size.width * 0.8
                let byHeight = (width: maxHeight * 3.0 / 4.0, height: maxHeight)
                let guide: (width: CGFloat, height: CGFloat) =
                    byHeight.width <= maxWidth
                        ? byHeight
                        : (width: maxWidth, height: maxWidth * 4.0 / 3.0)
                Path { path in
                    let rect = CGRect(
                        x: (geo.size.width - guide.width) / 2.0,
                        y: (geo.size.height - guide.height) / 2.0,
                        width: guide.width,
                        height: guide.height
                    )
                    path.addRect(rect)
                }
                .stroke(style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .foregroundColor(.white.opacity(0.8))
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    Spacer()
                }
                Spacer()

                HStack {
                    Button(action: { model.toggleTorch() }) {
                        Image(systemName: model.torchOn ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(model.torchAvailable ? .white : .gray)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .disabled(!model.torchAvailable)

                    Spacer()

                    Button(action: {
                        model.capture { image in
                            if let image { onImagePicked(image) }
                        }
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 4)
                                        .frame(width: 84, height: 84))
                    }

                    Spacer().frame(width: 60)   // balance the torch column
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct CapturePreview: UIViewRepresentable {
    let model: CaptureModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: model.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.layer = layer
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.layer?.frame = uiView.bounds
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var layer: AVCaptureVideoPreviewLayer?
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var pendingCompletion: ((UIImage?) -> Void)?

    @Published var torchOn = false
    @Published var torchAvailable = false

    func start() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            device = dev
            torchAvailable = dev.hasTorch
            if let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) {
                session.addInput(input)
            }
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.isHighResolutionCaptureEnabled = true
        }
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stop() {
        if torchOn { toggleTorch() }
        session.stopRunning()
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if torchOn {
                device.torchMode = .off
                torchOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                torchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            // If torch lock fails, silently leave state unchanged.
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        pendingCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()
        Task { @MainActor in
            self.pendingCompletion?(image)
            self.pendingCompletion = nil
        }
    }
}
