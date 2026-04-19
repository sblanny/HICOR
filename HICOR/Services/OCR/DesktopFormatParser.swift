import Foundation

enum DesktopFormatParser {

    static func parse(lines rawLines: [String], photoIndex: Int) -> PrintoutResult {
        let lines = rawLines.map(ReadingNormalizer.normalizeOCRString)

        // Accept OCR variants for the section markers observed on real
        // GRK-6000 thermal captures: `<R>` often misreads as `<A>` (R and A
        // share diagonal strokes in a matrix font), and `<L>` can lose its
        // leading `<` when the thin vertical stroke fades. Without these
        // variants, sliceSection returns empty and the eye loses all
        // readings downstream.
        let rightMarkers = ["[R]", "<R>", "<A>"]
        let leftMarkers  = ["[L]", "<L>", "L>"]
        let terminalMarkers = ["PD", "GRK", "GAK"]

        let rightSection = sliceSection(
            lines: lines,
            startMarkers: rightMarkers,
            endMarkers: leftMarkers + terminalMarkers
        )
        let leftSection = sliceSection(
            lines: lines,
            startMarkers: leftMarkers,
            endMarkers: rightMarkers + terminalMarkers
        )

        let rightParsed = parseEyeSection(rightSection, eye: .right, photoIndex: photoIndex)
        let leftParsed  = parseEyeSection(leftSection,  eye: .left,  photoIndex: photoIndex)

        let pd = extractPD(from: lines)

        return PrintoutResult(
            rightEye: rightParsed,
            leftEye: leftParsed,
            pd: pd,
            machineType: .desktop,
            sourcePhotoIndex: photoIndex,
            rawText: lines.joined(separator: "\n"),
            handheldStarConfidenceRight: nil,
            handheldStarConfidenceLeft: nil
        )
    }

    private static func sliceSection(
        lines: [String],
        startMarkers: [String],
        endMarkers: [String]
    ) -> [String] {
        guard let startIndex = lines.firstIndex(where: { line in
            startMarkers.contains(where: { line.contains($0) })
        }) else {
            return []
        }
        let after = Array(lines.suffix(from: lines.index(after: startIndex)))
        var section: [String] = []
        for line in after {
            if endMarkers.contains(where: { line.contains($0) }) {
                break
            }
            section.append(line)
        }
        return section
    }

    private static func parseEyeSection(_ lines: [String], eye: Eye, photoIndex: Int) -> EyeReading? {
        // First pass: locate the AVG line. On the GRK-6000 printout AVG is
        // usually OCR'd more reliably than individual reading rows (larger
        // font, single triple per row), so its sign becomes the authoritative
        // hint for unsigned individual SPH tokens below. ML Kit drops thin
        // thermal-paper minus signs frequently, so we need a baseline.
        var avgSPH: Double?
        var avgCYL: Double?
        var avgAX: Int?
        for line in lines where line.uppercased().contains("AVG") {
            if let parsed = parseValueTriple(line: line, stripPrefix: "AVG", sphSignHint: nil) {
                avgSPH = ReadingNormalizer.normalize(sph: parsed.sph)
                avgCYL = ReadingNormalizer.normalize(cyl: parsed.cyl)
                avgAX  = ReadingNormalizer.normalize(ax: parsed.ax)
                break
            }
        }

        // Sign hint for unsigned individual SPH tokens. Trust AVG when we
        // have it; otherwise default to negative (the common case for this
        // mission population) and flag via parser log.
        let sphSignHint: Double
        if let avgSPH, avgSPH != 0 {
            sphSignHint = avgSPH < 0 ? -1 : 1
        } else {
            sphSignHint = -1
        }

        var readings: [RawReading] = []
        for line in lines {
            if line.uppercased().contains("AVG") { continue }
            if let parsed = parseValueTriple(line: line, stripPrefix: nil, sphSignHint: sphSignHint) {
                readings.append(RawReading(
                    id: UUID(),
                    sph: ReadingNormalizer.normalize(sph: parsed.sph),
                    cyl: parsed.isSphOnly ? 0.0 : ReadingNormalizer.normalize(cyl: parsed.cyl),
                    ax:  parsed.isSphOnly ? 0   : ReadingNormalizer.normalize(ax:  parsed.ax),
                    eye: eye,
                    sourcePhotoIndex: photoIndex,
                    isSphOnly: parsed.isSphOnly
                ))
            }
        }

        if readings.isEmpty && avgSPH == nil { return nil }

        return EyeReading(
            id: UUID(),
            eye: eye,
            readings: readings,
            machineAvgSPH: avgSPH,
            machineAvgCYL: avgCYL,
            machineAvgAX: avgAX,
            sourcePhotoIndex: photoIndex,
            machineType: .desktop
        )
    }

    static func parseValueTriple(
        line: String,
        stripPrefix: String?,
        sphSignHint: Double? = nil
    ) -> (sph: Double, cyl: Double, ax: Int, isSphOnly: Bool)? {
        var work = line
        let allowSphOnly = (stripPrefix == nil)  // AVG lines always carry all three values
        if let prefix = stripPrefix {
            if let range = work.range(of: prefix, options: .caseInsensitive) {
                work.removeSubrange(work.startIndex..<range.upperBound)
            }
        }
        let trimmed = work.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strict shape gate: SPH alone, OR SPH + CYL + AX. Each diopter token must be
        // a quarter-diopter decimal like "+ 1.50" or "- 21.00". Bare integers are
        // NEVER spheres or cylinders — they are axes or OCR fragmentation garbage.
        guard ReadingLineShape.matches(trimmed, allowQualityMarker: false) else {
            return nil
        }

        let tokens = combineSignTokens(trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let numerics = tokens.filter { Double($0) != nil }
        if numerics.count >= 3 {
            let sphToken = numerics[0]
            let cylToken = numerics[1]
            let axToken  = numerics[2]

            // Desktop header states "CYL (-)" — all cylinders are negative
            // by format. Reject explicit + CYL as OCR garbage; coerce
            // unsigned values to negative (ML Kit drops thin minus signs
            // on thermal paper).
            if cylToken.hasPrefix("+") {
                return nil
            }
            let cylSigned = cylToken.hasPrefix("-") ? cylToken : "-" + cylToken

            // Unsigned SPH takes the sign hint from AVG when provided.
            let sphSigned: String = {
                guard let hint = sphSignHint else { return sphToken }
                if sphToken.hasPrefix("+") || sphToken.hasPrefix("-") { return sphToken }
                return (hint < 0 ? "-" : "+") + sphToken
            }()

            if let sph = Double(sphSigned),
               let cyl = Double(cylSigned),
               let ax  = Int(axToken),
               ReadingPlausibility.isPlausibleSPH(sph),
               ReadingPlausibility.isPlausibleCYL(cyl),
               ReadingPlausibility.isPlausibleAX(ax) {
                return (sph, cyl, ax, false)
            }
        }
        if allowSphOnly,
           numerics.count == 1,
           numerics[0].contains(".") {
            let token = numerics[0]
            let signedToken: String = {
                guard let hint = sphSignHint,
                      !(token.hasPrefix("+") || token.hasPrefix("-")) else { return token }
                return (hint < 0 ? "-" : "+") + token
            }()
            if let sph = Double(signedToken), ReadingPlausibility.isPlausibleSPH(sph) {
                return (sph, 0.0, 0, true)
            }
        }
        return nil
    }

    static func combineSignTokens(_ tokens: [String]) -> [String] {
        var combined: [String] = []
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if (t == "+" || t == "-") && i + 1 < tokens.count, Double(tokens[i + 1]) != nil {
                combined.append(t + tokens[i + 1])
                i += 2
            } else {
                combined.append(t)
                i += 1
            }
        }
        return combined
    }

    private static func extractPD(from lines: [String]) -> Double? {
        let pattern = #"(?i)\bPD\b\s*[:=]?\s*(\d{2,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 {
                if let r = Range(match.range(at: 1), in: line), let value = Double(line[r]) {
                    return value
                }
            }
        }
        return nil
    }
}
