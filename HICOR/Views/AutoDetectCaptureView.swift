import AVFoundation
import SwiftUI
import UIKit

struct AutoDetectCaptureView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> AutoDetectCaptureController {
        let vc = AutoDetectCaptureController()
        vc.onImagePicked = onImagePicked
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: AutoDetectCaptureController, context: Context) {}
}

final class AutoDetectCaptureController: UIViewController,
                                         AVCaptureVideoDataOutputSampleBufferDelegate {
    var onImagePicked: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let l = AVCaptureVideoPreviewLayer(session: session)
        l.videoGravity = .resizeAspectFill
        return l
    }()

    private let detectionQueue = DispatchQueue(label: "hicor.capture.detection", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "hicor.capture.session", qos: .userInitiated)

    private let detector = RectangleDetector()
    private let stability = StabilityDetector(windowSize: 15, tolerance: 0.01)

    private let overlayView = OverlayUIView()
    private let statusLabel = UILabel()
    private let fallbackBanner = UILabel()
    private let shutterButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var latestRectangle: DetectedRectangle?
    private var isCaptureInFlight = false
    private var lastDetectionFireHost: CFTimeInterval = 0
    private var firstFrameTime: CFTimeInterval = 0
    private var fallbackShown = false

    private let detectionIntervalSeconds: CFTimeInterval = 0.1
    private let fallbackAfterSeconds: CFTimeInterval = 10

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    // AVCapturePhotoOutput only holds a weak reference to its delegate — keep them alive here.
    private var retainedDelegates: [AutoDetectPhotoCaptureDelegate] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayView.frame = view.bounds
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.setSampleBufferDelegate(self, queue: detectionQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            if let connection = videoDataOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
        }
        session.commitConfiguration()

        view.layer.addSublayer(previewLayer)
    }

    private func setupUI() {
        overlayView.translatesAutoresizingMaskIntoConstraints = true
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlayView.frame = view.bounds
        view.addSubview(overlayView)

        statusLabel.text = "Position the printout inside the frame"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.shadowColor = .black
        statusLabel.shadowOffset = CGSize(width: 0, height: 1)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        fallbackBanner.text = "Auto-detection unavailable — tap the shutter to capture manually."
        fallbackBanner.textColor = .white
        fallbackBanner.font = .systemFont(ofSize: 14, weight: .regular)
        fallbackBanner.textAlignment = .center
        fallbackBanner.numberOfLines = 0
        fallbackBanner.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        fallbackBanner.layer.cornerRadius = 10
        fallbackBanner.layer.masksToBounds = true
        fallbackBanner.isHidden = true
        fallbackBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fallbackBanner)

        let shutterConfig = UIImage.SymbolConfiguration(pointSize: 72)
        shutterButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: shutterConfig), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.addTarget(self, action: #selector(manualShutterTapped), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        let cancelConfig = UIImage.SymbolConfiguration(pointSize: 32)
        cancelButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: cancelConfig), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),

            fallbackBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            fallbackBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            fallbackBanner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    @objc private func manualShutterTapped() {
        triggerCapture(applyPerspectiveCorrection: false)
    }

    @objc private func cancelTapped() { onCancel?() }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        if firstFrameTime == 0 { firstFrameTime = now }
        guard now - lastDetectionFireHost >= detectionIntervalSeconds else { return }
        lastDetectionFireHost = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let results = detector.detect(in: pixelBuffer, orientation: .right)
        let top = results.first
        stability.append(top)

        let newState: CaptureOverlayState
        if top == nil { newState = .searching }
        else if stability.isStable { newState = .locked }
        else { newState = .detecting }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestRectangle = top
            self.overlayView.update(rectangle: top, state: newState)
            self.updateStatusText(state: newState, sinceFirstFrame: now - self.firstFrameTime)

            if newState == .locked && !self.isCaptureInFlight {
                self.playLockPulse()
                self.triggerCapture(applyPerspectiveCorrection: true)
            }
        }
    }

    private func updateStatusText(state: CaptureOverlayState, sinceFirstFrame: CFTimeInterval) {
        switch state {
        case .searching:
            statusLabel.text = "Position the printout inside the frame"
        case .detecting:
            statusLabel.text = "Hold still..."
        case .locked:
            statusLabel.text = "Capturing..."
        }
        if sinceFirstFrame > fallbackAfterSeconds && !fallbackShown && state == .searching {
            fallbackShown = true
            fallbackBanner.isHidden = false
            UIView.animate(withDuration: 0.25) {
                self.shutterButton.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }
        }
        // Once a rectangle is detected after fallback surfaced, hide the banner — auto-capture
        // takes over. The banner having appeared is a user-visible signal (not silently
        // swallowed) per feedback_surface_automatic_exclusions.md.
        if fallbackShown && state != .searching {
            fallbackBanner.isHidden = true
        }
    }

    private func triggerCapture(applyPerspectiveCorrection: Bool) {
        haptic.prepare()
        haptic.impactOccurred()
        isCaptureInFlight = true
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        let delegate = AutoDetectPhotoCaptureDelegate(
            applyCorrection: applyPerspectiveCorrection,
            rectangle: applyPerspectiveCorrection ? latestRectangle : nil
        ) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCaptureInFlight = false
                if let image { self.onImagePicked?(image) }
            }
        }
        retainedDelegates.append(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        flashScreen()
    }

    private func playLockPulse() {
        let ring = CAShapeLayer()
        ring.frame = view.bounds
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.systemGreen.cgColor
        ring.lineWidth = 4
        ring.path = UIBezierPath(ovalIn: CGRect(x: view.bounds.midX - 40,
                                                y: view.bounds.midY - 40,
                                                width: 80, height: 80)).cgPath
        overlayView.layer.addSublayer(ring)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.5
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        ring.add(group, forKey: "pulse")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ring.removeFromSuperlayer() }
    }

    // Fires immediately when the shutter is invoked — this is the user-facing cue for
    // "I'm capturing now," not a confirmation that the photo came back successfully. The
    // async photo-processing path can still fail or be cancelled; the flash is intentionally
    // decoupled so the UI feels responsive on the same frame as the haptic.
    private func flashScreen() {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.08, animations: { flash.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.18, animations: { flash.alpha = 0 }) { _ in
                flash.removeFromSuperview()
            }
        }
    }
}

private final class AutoDetectPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let applyCorrection: Bool
    private let rectangle: DetectedRectangle?
    private let completion: (UIImage?) -> Void

    init(applyCorrection: Bool,
         rectangle: DetectedRectangle?,
         completion: @escaping (UIImage?) -> Void) {
        self.applyCorrection = applyCorrection
        self.rectangle = rectangle
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion(nil); return
        }
        guard applyCorrection, let rect = rectangle else {
            completion(image); return
        }
        // Rectangle corners are normalized UIKit space. Scale to image pixel space before correction.
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let corners = QuadCorners(
            topLeft:     CGPoint(x: rect.topLeft.x     * w, y: rect.topLeft.y     * h),
            topRight:    CGPoint(x: rect.topRight.x    * w, y: rect.topRight.y    * h),
            bottomRight: CGPoint(x: rect.bottomRight.x * w, y: rect.bottomRight.y * h),
            bottomLeft:  CGPoint(x: rect.bottomLeft.x  * w, y: rect.bottomLeft.y  * h)
        )
        completion(PerspectiveCorrector.correct(image: image, corners: corners) ?? image)
    }
}
