import Foundation

enum DesktopFormatParser {

    static func parse(lines rawLines: [String], photoIndex: Int) -> PrintoutResult {
        let lines = rawLines.map(ReadingNormalizer.normalizeOCRString)

        let rightSection = sliceSection(lines: lines, startMarker: "[R]", altMarker: "<R>")
        let leftSection  = sliceSection(lines: lines, startMarker: "[L]", altMarker: "<L>")

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

    private static func sliceSection(lines: [String], startMarker: String, altMarker: String) -> [String] {
        guard let startIndex = lines.firstIndex(where: { $0.contains(startMarker) || $0.contains(altMarker) }) else {
            return []
        }
        let after = Array(lines.suffix(from: lines.index(after: startIndex)))
        let endMarkers = ["[L]", "<L>", "[R]", "<R>", "PD"]
        var section: [String] = []
        for line in after {
            if endMarkers.contains(where: { line.contains($0) && !line.contains(startMarker) && !line.contains(altMarker) }) {
                break
            }
            section.append(line)
        }
        return section
    }

    private static func parseEyeSection(_ lines: [String], eye: Eye, photoIndex: Int) -> EyeReading? {
        var readings: [RawReading] = []
        var avgSPH: Double?
        var avgCYL: Double?
        var avgAX: Int?

        for line in lines {
            let upper = line.uppercased()
            if upper.contains("AVG") {
                if let parsed = parseValueTriple(line: line, stripPrefix: "AVG") {
                    avgSPH = ReadingNormalizer.normalize(sph: parsed.sph)
                    avgCYL = ReadingNormalizer.normalize(cyl: parsed.cyl)
                    avgAX  = ReadingNormalizer.normalize(ax: parsed.ax)
                }
                continue
            }
            if let parsed = parseValueTriple(line: line, stripPrefix: nil) {
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

    static func parseValueTriple(line: String, stripPrefix: String?) -> (sph: Double, cyl: Double, ax: Int, isSphOnly: Bool)? {
        var work = line
        let allowSphOnly = (stripPrefix == nil)  // AVG lines always carry all three values
        if let prefix = stripPrefix {
            if let range = work.range(of: prefix, options: .caseInsensitive) {
                work.removeSubrange(work.startIndex..<range.upperBound)
            }
        }
        let tokens = combineSignTokens(work.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        let numerics = tokens.filter { Double($0) != nil }
        if numerics.count >= 3,
           let sph = Double(numerics[0]),
           let cyl = Double(numerics[1]),
           let ax  = Int(numerics[2]) {
            return (sph, cyl, ax, false)
        }
        if allowSphOnly, numerics.count == 1, let sph = Double(numerics[0]) {
            return (sph, 0.0, 0, true)
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
