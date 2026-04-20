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
    private let gridLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = 3
        shapeLayer.lineJoin = .round
        gridLayer.fillColor = UIColor.clear.cgColor
        gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        gridLayer.lineWidth = 1
        layer.addSublayer(shapeLayer)
        layer.addSublayer(gridLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
        gridLayer.frame = bounds
    }

    func update(rectangle: DetectedRectangle?, state: CaptureOverlayState) {
        guard let r = rectangle else {
            shapeLayer.path = nil
            gridLayer.path = nil
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

        // Interior grid: three lines parallel to top edge at 0.25 / 0.50 / 0.75 of the quad height.
        let tl = denorm(r.topLeft)
        let tr = denorm(r.topRight)
        let bl = denorm(r.bottomLeft)
        let br = denorm(r.bottomRight)
        let lerp: (CGPoint, CGPoint, CGFloat) -> CGPoint = { a, b, t in
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let grid = UIBezierPath()
        for t in [0.25, 0.5, 0.75] {
            grid.move(to: lerp(tl, bl, CGFloat(t)))
            grid.addLine(to: lerp(tr, br, CGFloat(t)))
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        shapeLayer.path = path.cgPath
        gridLayer.path = grid.cgPath
        switch state {
        case .searching:
            shapeLayer.strokeColor = UIColor.clear.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            gridLayer.strokeColor = UIColor.clear.cgColor
        case .detecting:
            shapeLayer.strokeColor = UIColor.systemBlue.cgColor
            shapeLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15).cgColor
            gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        case .locked:
            shapeLayer.strokeColor = UIColor.systemGreen.cgColor
            shapeLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25).cgColor
            gridLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        }
        CATransaction.commit()
    }
}
