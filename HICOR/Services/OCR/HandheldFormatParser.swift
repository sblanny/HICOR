import Foundation

enum HandheldFormatParser {

    static func parse(lines rawLines: [String], photoIndex: Int) -> PrintoutResult {
        let lines = rawLines.map(ReadingNormalizer.normalizeOCRString)

        var rightLines: [String] = []
        var leftLines: [String] = []
        var seenRefMarker = false
        var inSection: Eye?
        for line in lines {
            if line.contains("-REF-") || line.contains("REF-") || line.contains("-REF") {
                seenRefMarker = true
                continue
            }
            if !seenRefMarker { continue }
            if line.contains("[R]") || line.contains("<R>") {
                inSection = .right
                continue
            }
            if line.contains("[L]") || line.contains("<L>") {
                inSection = .left
                continue
            }
            switch inSection {
            case .right: rightLines.append(line)
            case .left:  leftLines.append(line)
            case nil:    break
            }
        }

        let right = parseEyeSection(rightLines, eye: .right, photoIndex: photoIndex)
        let left  = parseEyeSection(leftLines,  eye: .left,  photoIndex: photoIndex)

        return PrintoutResult(
            rightEye: right.reading,
            leftEye:  left.reading,
            pd: nil,
            machineType: .handheld,
            sourcePhotoIndex: photoIndex,
            rawText: lines.joined(separator: "\n"),
            handheldStarConfidenceRight: right.starConfidence,
            handheldStarConfidenceLeft:  left.starConfidence
        )
    }

    private static func parseEyeSection(
        _ lines: [String],
        eye: Eye,
        photoIndex: Int
    ) -> (reading: EyeReading?, starConfidence: Int?) {
        var readings: [RawReading] = []
        var avgSPH: Double?
        var avgCYL: Double?
        var avgAX: Int?
        var starConfidence: Int?

        for line in lines {
            if line.contains("*") {
                if let parsed = parseStarLine(line) {
                    avgSPH = ReadingNormalizer.normalize(sph: parsed.sph)
                    avgCYL = ReadingNormalizer.normalize(cyl: parsed.cyl)
                    avgAX  = ReadingNormalizer.normalize(ax:  parsed.ax)
                    starConfidence = parsed.confidence
                }
                continue
            }
            if let parsed = parseReadingLine(line) {
                readings.append(RawReading(
                    id: UUID(),
                    sph: ReadingNormalizer.normalize(sph: parsed.sph),
                    cyl: parsed.isSphOnly ? 0.0 : ReadingNormalizer.normalize(cyl: parsed.cyl),
                    ax:  parsed.isSphOnly ? 0   : ReadingNormalizer.normalize(ax:  parsed.ax),
                    eye: eye,
                    sourcePhotoIndex: photoIndex,
                    lowConfidence: parsed.lowConfidence,
                    isSphOnly: parsed.isSphOnly
                ))
            }
        }

        if readings.isEmpty && avgSPH == nil {
            return (nil, starConfidence)
        }

        let er = EyeReading(
            id: UUID(),
            eye: eye,
            readings: readings,
            machineAvgSPH: avgSPH,
            machineAvgCYL: avgCYL,
            machineAvgAX:  avgAX,
            sourcePhotoIndex: photoIndex,
            machineType: .handheld
        )
        return (er, starConfidence)
    }

    static func parseReadingLine(_ line: String) -> (sph: Double, cyl: Double, ax: Int, lowConfidence: Bool, isSphOnly: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strict shape gate: SPH alone, OR SPH + CYL + AX, optionally trailed by
        // AQ/E. Each diopter token must be a quarter-diopter decimal — bare
        // integer tokens are NEVER spheres or cylinders, only axes or garbage.
        guard ReadingLineShape.matches(trimmed, allowQualityMarker: true) else {
            print("Parser: rejecting handheld line '\(line)' — reason: shape mismatch")
            return nil
        }

        let tokens = DesktopFormatParser.combineSignTokens(
            trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        )
        let qualityToken = tokens.last.flatMap { $0 == "AQ" || $0 == "E" ? $0 : nil }
        let numerics = tokens.compactMap { Double($0) != nil ? $0 : nil }
        if numerics.count >= 3,
           let sph = Double(numerics[0]),
           let cyl = Double(numerics[1]),
           let ax  = Int(numerics[2]),
           ReadingPlausibility.isPlausibleSPH(sph),
           ReadingPlausibility.isPlausibleCYL(cyl),
           ReadingPlausibility.isPlausibleAX(ax) {
            print("Parser: accepted handheld line '\(line)' as SPH=\(sph) CYL=\(cyl) AX=\(ax)")
            return (sph, cyl, ax, qualityToken == "E", false)
        }
        // Machine printed SPH only (no astigmatism detected on this measurement).
        if numerics.count == 1,
           numerics[0].contains("."),
           let sph = Double(numerics[0]),
           ReadingPlausibility.isPlausibleSPH(sph) {
            print("Parser: accepted handheld SPH-only line '\(line)' as SPH=\(sph)")
            return (sph, 0.0, 0, qualityToken == "E", true)
        }
        print("Parser: rejecting handheld line '\(line)' — reason: range or token count")
        return nil
    }

    static func parseStarLine(_ line: String) -> (sph: Double, cyl: Double, ax: Int, confidence: Int?)? {
        var work = line
        if let starRange = work.range(of: "*") {
            work.removeSubrange(work.startIndex..<starRange.upperBound)
        }
        let tokens = DesktopFormatParser.combineSignTokens(
            work.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        )
        let numerics = tokens.compactMap { Double($0) != nil ? $0 : nil }
        guard numerics.count >= 3,
              let sph = Double(numerics[0]),
              let cyl = Double(numerics[1]),
              let ax  = Int(numerics[2])
        else {
            return nil
        }
        var confidence: Int?
        if numerics.count >= 4, let conf = Int(numerics[3]), (1...9).contains(conf) {
            confidence = conf
        }
        return (sph, cyl, ax, confidence)
    }
}
