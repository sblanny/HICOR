import CoreGraphics

final class StabilityDetector {
    let windowSize: Int
    let tolerance: CGFloat

    private var history: [DetectedRectangle] = []

    init(windowSize: Int = 15, tolerance: CGFloat = 10) {
        self.windowSize = windowSize
        self.tolerance = tolerance
    }

    func append(_ rect: DetectedRectangle?) {
        guard let rect else {
            history.removeAll()
            return
        }
        history.append(rect)
        if history.count > windowSize {
            history.removeFirst(history.count - windowSize)
        }
    }

    var isStable: Bool {
        guard history.count == windowSize else { return false }
        return cornersWithinTolerance(\.topLeft)
            && cornersWithinTolerance(\.topRight)
            && cornersWithinTolerance(\.bottomRight)
            && cornersWithinTolerance(\.bottomLeft)
    }

    var current: DetectedRectangle? { history.last }

    func reset() { history.removeAll() }

    private func cornersWithinTolerance(_ keyPath: KeyPath<DetectedRectangle, CGPoint>) -> Bool {
        let points = history.map { $0[keyPath: keyPath] }
        let medianX = median(points.map(\.x))
        let medianY = median(points.map(\.y))
        return points.allSatisfy { abs($0.x - medianX) <= tolerance && abs($0.y - medianY) <= tolerance }
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
