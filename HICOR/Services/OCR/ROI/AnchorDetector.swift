import UIKit

class AnchorDetector {

    enum Error: Swift.Error, Equatable {
        case insufficientAnchors(missing: [String])
    }

    private let recognizer: LineRecognizing

    init(recognizer: LineRecognizing) {
        self.recognizer = recognizer
    }

    func detectAnchors(in image: UIImage) async throws -> Anchors {
        let lines = try await recognizer.recognize(image)
        return try detectAnchors(from: lines)
    }

    /// Pure variant used when the caller has already recognized the image
    /// (e.g. ROIPipelineExtractor wants to reuse the element list for both
    /// anchor detection and per-cell value picking — halves the ML Kit
    /// calls and avoids re-OCR quality issues on tiny cell crops).
    func detectAnchors(from lines: [OCRLine]) throws -> Anchors {
        let rMarker = lines.first(where: { matchesRightMarker($0.text) })
        let lMarker = lines.first(where: { matchesLeftMarker($0.text) })

        let sphMatches = lines.filter { matchesColumnHeader($0.text, target: "SPH") }
        let rawCylMatches = lines.filter { matchesColumnHeader($0.text, target: "CYL") }
        let axMatches  = lines.filter { matchesColumnHeader($0.text, target: "AX") }
        let avgMatches = lines.filter { matchesColumnHeader($0.text, target: "AVG") }

        // Exclude the global "CYL (-)" polarity label that appears near the
        // top of the slip on the "VD = 0mm  CYL (-)" row. It's NOT a per-eye
        // column header and including it skews the section split heuristic.
        // Reliable signature: a per-eye CYL header is flanked horizontally by
        // SPH and/or AX headers on the same row band; the global CYL label
        // sits alone on its row with no SPH/AX neighbors. Row band = ±1.2×
        // header height (accommodates baseline jitter on dim prints).
        let cylMatches = rawCylMatches.filter { cyl in
            let ySlop = cyl.frame.height * 1.2
            let hasRowNeighbor = (sphMatches + axMatches).contains { neighbor in
                abs(neighbor.frame.midY - cyl.frame.midY) < ySlop
            }
            return hasRowNeighbor
        }

        // Section split. Two strategies depending on what survived filtering:
        //   A. Both eyes have column headers → biggest Y-gap in the header
        //      list brackets the eye-to-eye boundary. AVG is excluded because
        //      the within-section header→AVG gap can rival or exceed the
        //      between-section gap, pulling the split to the wrong place.
        //   B. Only one eye's headers survive (dim capture drops the other
        //      eye's SPH/CYL/AX entirely) → fall back to AVG-to-AVG midpoint.
        //      Each eye prints exactly one AVG; as long as both are detected
        //      the midpoint lies between the two sections.
        let hasBothEyesHeaders = sphMatches.count >= 2 || cylMatches.count >= 2 || axMatches.count >= 2
        let sectionSplitY: CGFloat
        if hasBothEyesHeaders {
            let headerYs = (sphMatches + cylMatches + axMatches)
                .map { $0.frame.midY }
                .sorted()
            guard headerYs.count >= 2 else {
                throw Error.insufficientAnchors(missing: ["column headers (found \(headerYs.count), need ≥2)"])
            }
            var biggest: (lo: CGFloat, hi: CGFloat) = (headerYs[0], headerYs[0])
            for i in 1..<headerYs.count {
                if headerYs[i] - headerYs[i - 1] > biggest.hi - biggest.lo {
                    biggest = (headerYs[i - 1], headerYs[i])
                }
            }
            sectionSplitY = (biggest.lo + biggest.hi) / 2.0
        } else if avgMatches.count >= 2 {
            let avgYs = avgMatches.map(\.frame.midY).sorted()
            sectionSplitY = (avgYs[0] + avgYs[1]) / 2.0
        } else {
            throw Error.insufficientAnchors(missing: ["column headers or AVG markers for both eyes"])
        }

        // On GRK-6000 desktop prints the right eye section is always on top
        // (printer convention). We still cross-check with any detected
        // <R>/<L> markers if available.
        let rightIsAbove: Bool
        if let r = rMarker, let l = lMarker {
            rightIsAbove = r.frame.midY < l.frame.midY
        } else if let r = rMarker {
            rightIsAbove = r.frame.midY < sectionSplitY
        } else if let l = lMarker {
            rightIsAbove = l.frame.midY >= sectionSplitY
        } else {
            rightIsAbove = true
        }

        func bandFor(_ section: Section) -> (wantAbove: Bool, refY: CGFloat) {
            let wantAbove = (section == .right) == rightIsAbove
            let axInBand = axMatches.first { wantAbove ? $0.frame.midY < sectionSplitY : $0.frame.midY >= sectionSplitY }
            let sphInBand = sphMatches.first { wantAbove ? $0.frame.midY < sectionSplitY : $0.frame.midY >= sectionSplitY }
            let cylInBand = cylMatches.first { wantAbove ? $0.frame.midY < sectionSplitY : $0.frame.midY >= sectionSplitY }
            let refY = axInBand?.frame.midY
                ?? sphInBand?.frame.midY
                ?? cylInBand?.frame.midY
                ?? (wantAbove ? sectionSplitY - 200 : sectionSplitY + 200)
            return (wantAbove, refY)
        }

        func pickColumnHeader(_ matches: [OCRLine], section: Section) -> CGRect? {
            let (wantAbove, refY) = bandFor(section)
            let filtered = matches.filter { wantAbove ? $0.frame.midY < sectionSplitY : $0.frame.midY >= sectionSplitY }
            return filtered.min(by: { abs($0.frame.midY - refY) < abs($1.frame.midY - refY) })?.frame
        }

        func pickAVG(section: Section) -> CGRect? {
            let (wantAbove, _) = bandFor(section)
            let filtered = avgMatches.filter { wantAbove ? $0.frame.midY < sectionSplitY : $0.frame.midY >= sectionSplitY }
            // AVG sits BELOW the column headers within a section. Prefer the
            // match with the largest Y (wantAbove) or smallest Y (below).
            // Actually either way, there's usually only one AVG per section.
            return filtered.max(by: { $0.frame.midY < $1.frame.midY })?.frame
        }

        let rightSPH = pickColumnHeader(sphMatches, section: .right)
        let rightCYL = pickColumnHeader(cylMatches, section: .right)
        let rightAX  = pickColumnHeader(axMatches,  section: .right)
        let rightAVG = pickAVG(section: .right)
        let leftSPH  = pickColumnHeader(sphMatches, section: .left)
        let leftCYL  = pickColumnHeader(cylMatches, section: .left)
        let leftAX   = pickColumnHeader(axMatches,  section: .left)
        let leftAVG  = pickAVG(section: .left)

        // CellLayout uses SPH/CYL/AX/AVG rects (not eyeMarker) to compute
        // cell geometry. Eye markers are only informational, so we accept
        // any of the following fallbacks for the eyeMarker slot.
        let rightEye = rMarker?.frame ?? rightSPH ?? .zero
        let leftEye  = lMarker?.frame ?? leftSPH  ?? .zero

        let right = try assembleSection(
            label: "right",
            eyeMarker: rightEye,
            sph: rightSPH, cyl: rightCYL, ax: rightAX, avg: rightAVG
        )
        let left = try assembleSection(
            label: "left",
            eyeMarker: leftEye,
            sph: leftSPH, cyl: leftCYL, ax: leftAX, avg: leftAVG
        )
        return Anchors(right: right, left: left)
    }

    private enum Section { case right, left }

    // ML Kit routinely misreads the angle brackets on dim thermal prints:
    // `<R>` shows up as `KR>`, `<R)`, `<R]`, `(R>`, etc; `<L>` as `KL>`,
    // `<l>`, `(1)`, `<I>`. Rules: length ≤ 4, must end with a bracket-like
    // close (`>`, `]`, `)`), must contain the letter (R or L-like) right
    // before that close; anything preceding is treated as an open bracket
    // that ML Kit mangled.
    private static let rightMarkerRegex = try! NSRegularExpression(
        pattern: #"^.{0,2}R[>\]\)]$"#,
        options: [.caseInsensitive]
    )
    private static let leftMarkerRegex = try! NSRegularExpression(
        pattern: #"^.{0,2}[LI1l][>\]\)]$"#
    )

    private func matchesRightMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count <= 4 else { return false }
        let range = NSRange(t.startIndex..., in: t)
        return Self.rightMarkerRegex.firstMatch(in: t, range: range) != nil
    }

    private func matchesLeftMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard t.count <= 4 else { return false }
        let range = NSRange(t.startIndex..., in: t)
        return Self.leftMarkerRegex.firstMatch(in: t, range: range) != nil
    }

    // Accepts target exactly, OR target + 1 trailing non-alpha char. So
    // "AVG-" matches AVG (trailing dash), "SPH:" matches SPH. For 3+ char
    // labels, tolerates a single character substitution (SPH → SFH, AVG →
    // AvG). Short labels (AX) require exact match — a 1-edit window on a
    // 2-char token matches too many unrelated fragments.
    private func matchesColumnHeader(_ text: String, target: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        let candidate: String
        if t.count == target.count {
            candidate = t
        } else if t.count == target.count + 1, let last = t.last, !last.isLetter {
            candidate = String(t.dropLast())
        } else {
            return false
        }
        if target.count <= 2 { return candidate == target }
        var diffs = 0
        for (a, b) in zip(candidate, target) where a != b { diffs += 1 }
        return diffs <= 1
    }

    /// Build a SectionAnchors with single-missing-column interpolation. AVG
    /// must be present — its Y is the bottom anchor for CellLayout and we
    /// cannot reliably derive it from the column headers alone. At most one
    /// of SPH/CYL/AX may be missing; its position is reconstructed from the
    /// other two using the GRK-6000 column spacing ratio (SPH-CYL is ~1.4×
    /// the CYL-AX gap).
    private func assembleSection(
        label: String,
        eyeMarker: CGRect,
        sph: CGRect?, cyl: CGRect?, ax: CGRect?, avg: CGRect?
    ) throws -> SectionAnchors {
        guard let avg else {
            throw Error.insufficientAnchors(missing: ["\(label) AVG"])
        }
        let columnsPresent = [sph, cyl, ax].compactMap { $0 }.count
        guard columnsPresent >= 2 else {
            let missing = [("SPH", sph), ("CYL", cyl), ("AX", ax)]
                .compactMap { $0.1 == nil ? "\(label) \($0.0)" : nil }
            throw Error.insufficientAnchors(missing: missing)
        }

        let resolvedSPH = sph ?? interpolateColumn(target: "SPH", cyl: cyl, ax: ax, sph: sph)
        let resolvedCYL = cyl ?? interpolateColumn(target: "CYL", cyl: cyl, ax: ax, sph: sph)
        let resolvedAX  = ax  ?? interpolateColumn(target: "AX",  cyl: cyl, ax: ax, sph: sph)

        return SectionAnchors(
            eyeMarker: eyeMarker,
            sph: resolvedSPH,
            cyl: resolvedCYL,
            ax:  resolvedAX,
            avg: avg
        )
    }

    /// Reconstruct a missing column header rect from the two present ones.
    /// The SPH-CYL physical gap on the GRK-6000 is roughly 1.4× the CYL-AX
    /// gap (measured across captures: 0.65-0.73 for AX-CYL / CYL-SPH). We
    /// use that ratio to locate the missing column's midX. The Y and size
    /// are copied from the nearest present column so CellLayout's header
    /// baseline stays consistent.
    private func interpolateColumn(
        target: String,
        cyl: CGRect?, ax: CGRect?, sph: CGRect?
    ) -> CGRect {
        let present: [CGRect] = [sph, cyl, ax].compactMap { $0 }
        let refMidY = present.map { $0.midY }.reduce(0, +) / CGFloat(present.count)
        let refWidth = present.map { $0.width }.reduce(0, +) / CGFloat(present.count)
        let refHeight = present.map { $0.height }.reduce(0, +) / CGFloat(present.count)

        let midX: CGFloat
        switch target {
        case "SPH":
            // SPH = CYL - 1.4 × (AX - CYL)
            midX = cyl!.midX - 1.4 * (ax!.midX - cyl!.midX)
        case "CYL":
            // CYL sits ~58% from SPH toward AX (1.4:1 gap ratio)
            midX = sph!.midX + 0.583 * (ax!.midX - sph!.midX)
        case "AX":
            // AX = CYL + (CYL - SPH) / 1.4
            midX = cyl!.midX + (cyl!.midX - sph!.midX) / 1.4
        default:
            midX = present.first!.midX
        }
        return CGRect(
            x: midX - refWidth / 2,
            y: refMidY - refHeight / 2,
            width: refWidth,
            height: refHeight
        )
    }
}
