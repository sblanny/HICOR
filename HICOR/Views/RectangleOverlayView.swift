import SwiftUI
import UIKit

enum CaptureOverlayState {
    case searching
    case detecting
    case locked
}

struct RectangleOverlayView: UIViewRepresentable {
    let rectangle: DetectedRectangle?
    let state: CaptureOverlayState

    func makeUIView(context: Context) -> OverlayUIView { OverlayUIView() }

    func updateUIView(_ uiView: OverlayUIView, context: Context) {
        uiView.update(rectangle: rectangle, state: state)
    }
}

final class OverlayUIView: UIView {
    private let shapeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 3
        shapeLayer.lineJoin = .round
        layer.addSublayer(shapeLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
    }

    func update(rectangle: DetectedRectangle?, state: CaptureOverlayState) {
        guard let r = rectangle else {
            shapeLayer.path = nil
            return
        }
        // Rectangle corners arrive in UIKit-normalized (0–1, top-left) coordinates.
        let denorm: (CGPoint) -> CGPoint = {
            CGPoint(x: $0.x * self.bounds.width, y: $0.y * self.bounds.height)
        }
        let path = UIBezierPath()
        path.move(to: denorm(r.topLeft))
        path.addLine(to: denorm(r.topRight))
        path.addLine(to: denorm(r.bottomRight))
        path.addLine(to: denorm(r.bottomLeft))
        path.close()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        shapeLayer.path = path.cgPath
        switch state {
        case .searching:
            shapeLayer.strokeColor = UIColor.clear.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
        case .detecting:
            shapeLayer.strokeColor = UIColor.systemBlue.cgColor
            shapeLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15).cgColor
        case .locked:
            shapeLayer.strokeColor = UIColor.systemGreen.cgColor
            shapeLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25).cgColor
        }
        CATransaction.commit()
    }
}
