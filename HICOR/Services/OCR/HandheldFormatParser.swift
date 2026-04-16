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
                    cyl: ReadingNormalizer.normalize(cyl: parsed.cyl),
                    ax:  ReadingNormalizer.normalize(ax:  parsed.ax),
                    eye: eye,
                    sourcePhotoIndex: photoIndex,
                    lowConfidence: parsed.lowConfidence
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

    static func parseReadingLine(_ line: String) -> (sph: Double, cyl: Double, ax: Int, lowConfidence: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = DesktopFormatParser.combineSignTokens(
            trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        )
        let qualityToken = tokens.last.flatMap { $0 == "AQ" || $0 == "E" ? $0 : nil }
        let numerics = tokens.compactMap { Double($0) != nil ? $0 : nil }
        guard numerics.count >= 3,
              let sph = Double(numerics[0]),
              let cyl = Double(numerics[1]),
              let ax  = Int(numerics[2])
        else {
            return nil
        }
        return (sph, cyl, ax, qualityToken == "E")
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
