import UIKit

final class AnchorDetector {

    enum Error: Swift.Error, Equatable {
        case insufficientAnchors(missing: [String])
    }

    private let recognizer: LineRecognizing

    init(recognizer: LineRecognizing) {
        self.recognizer = recognizer
    }

    func detectAnchors(in image: UIImage) async throws -> Anchors {
        let lines = try await recognizer.recognize(image)

        // Locate eye markers first — they set the vertical bands.
        guard let rMarker = lines.first(where: { matchesRightMarker($0.text) }) else {
            throw Error.insufficientAnchors(missing: ["<R>"])
        }
        guard let lMarker = lines.first(where: { matchesLeftMarker($0.text) }) else {
            throw Error.insufficientAnchors(missing: ["<L>"])
        }

        // Section split: the GRK-6000 places each eye marker at the TOP of
        // its section, so distance-to-marker misclassifies anchors at the
        // bottom of the top section (they're closer to the other marker).
        // Instead, find the axis along which the markers are most separated,
        // and split anchors at the "later" marker's leading edge: everything
        // before that line belongs to the earlier marker's section, everything
        // at-or-after belongs to the later marker's section.
        let dy = abs(rMarker.frame.midY - lMarker.frame.midY)
        let dx = abs(rMarker.frame.midX - lMarker.frame.midX)
        let splitVertical = dy >= dx
        let rIsFirst: Bool = splitVertical
            ? rMarker.frame.midY < lMarker.frame.midY
            : rMarker.frame.midX < lMarker.frame.midX
        let laterMarkerEdge: CGFloat = splitVertical
            ? (rIsFirst ? lMarker.frame.midY : rMarker.frame.midY)
            : (rIsFirst ? lMarker.frame.midX : rMarker.frame.midX)

        func sectionFor(_ line: OCRLine) -> Section {
            let pos = splitVertical ? line.frame.midY : line.frame.midX
            let isEarlySection = pos < laterMarkerEdge
            let earlySection: Section = rIsFirst ? .right : .left
            return isEarlySection ? earlySection : (earlySection == .right ? .left : .right)
        }

        var rightSPH: CGRect?, rightCYL: CGRect?, rightAX: CGRect?, rightAVG: CGRect?
        var leftSPH:  CGRect?, leftCYL:  CGRect?, leftAX:  CGRect?, leftAVG:  CGRect?

        for line in lines {
            let upper = line.text.uppercased()
            let section = sectionFor(line)
            switch upper {
            case "SPH":
                if section == .right { rightSPH = line.frame } else { leftSPH = line.frame }
            case "CYL":
                if section == .right { rightCYL = line.frame } else { leftCYL = line.frame }
            case "AX":
                if section == .right { rightAX = line.frame } else { leftAX = line.frame }
            case "AVG":
                if section == .right { rightAVG = line.frame } else { leftAVG = line.frame }
            default:
                continue
            }
        }

        let right = try assembleSection(
            label: "right",
            eyeMarker: rMarker.frame,
            sph: rightSPH, cyl: rightCYL, ax: rightAX, avg: rightAVG
        )
        let left = try assembleSection(
            label: "left",
            eyeMarker: lMarker.frame,
            sph: leftSPH, cyl: leftCYL, ax: leftAX, avg: leftAVG
        )
        return Anchors(right: right, left: left)
    }

    private enum Section { case right, left }

    private func matchesRightMarker(_ text: String) -> Bool {
        let up = text.uppercased().trimmingCharacters(in: .whitespaces)
        return up == "<R>" || up == "[R]"
    }

    private func matchesLeftMarker(_ text: String) -> Bool {
        let up = text.uppercased().trimmingCharacters(in: .whitespaces)
        return up == "<L>" || up == "[L]"
    }

    /// Build a SectionAnchors with single-missing-anchor interpolation.
    /// Any section missing 2+ of {SPH, CYL, AX, AVG} throws.
    private func assembleSection(
        label: String,
        eyeMarker: CGRect,
        sph: CGRect?, cyl: CGRect?, ax: CGRect?, avg: CGRect?
    ) throws -> SectionAnchors {
        let present = [("SPH", sph), ("CYL", cyl), ("AX", ax), ("AVG", avg)]
            .filter { $0.1 != nil }
        if present.count < 3 {
            let missing = [("SPH", sph), ("CYL", cyl), ("AX", ax), ("AVG", avg)]
                .compactMap { $0.1 == nil ? "\(label) \($0.0)" : nil }
            throw Error.insufficientAnchors(missing: missing)
        }

        let resolvedSPH = sph ?? interpolate(target: "SPH", sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedCYL = cyl ?? interpolate(target: "CYL", sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedAX  = ax  ?? interpolate(target: "AX",  sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedAVG = avg ?? interpolate(target: "AVG", sph: sph, cyl: cyl, ax: ax, avg: avg)

        return SectionAnchors(
            eyeMarker: eyeMarker,
            sph: resolvedSPH,
            cyl: resolvedCYL,
            ax:  resolvedAX,
            avg: resolvedAVG
        )
    }

    /// Single-missing interpolation by linear extrapolation on Y. Column
    /// labels on the GRK-6000 are equally spaced (SPH → CYL → AX → AVG),
    /// so missing CYL = midpoint(SPH, AX); missing AX = midpoint(CYL, AVG);
    /// missing SPH = CYL − (AX − CYL); missing AVG = AX + (AX − CYL).
    /// X and size are copied from the adjacent anchor (they don't vary
    /// across a column on the GRK-6000 layout).
    private func interpolate(
        target: String,
        sph: CGRect?, cyl: CGRect?, ax: CGRect?, avg: CGRect?
    ) -> CGRect {
        let template = sph ?? cyl ?? ax ?? avg!
        let size = template.size
        let x = template.origin.x

        let y: CGFloat
        switch target {
        case "SPH":
            y = 2 * cyl!.minY - ax!.minY
        case "CYL":
            y = (sph!.minY + ax!.minY) / 2.0
        case "AX":
            y = (cyl!.minY + avg!.minY) / 2.0
        case "AVG":
            y = 2 * ax!.minY - cyl!.minY
        default:
            y = template.minY
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
