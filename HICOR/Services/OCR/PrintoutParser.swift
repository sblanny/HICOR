import Foundation

enum PrintoutFormatDetectionResult {
    case desktop
    case handheld
    case unknown
}

enum PrintoutParser {

    static func detect(lines: [String]) -> PrintoutFormatDetectionResult {
        let blob = lines.joined(separator: " ").uppercased()
        if blob.contains("-REF-") || blob.contains("REF-") {
            return .handheld
        }
        if blob.contains("AVG") || blob.contains("GRK") || blob.contains("HIGHLANDS OPTICAL") {
            return .desktop
        }
        if blob.contains("*") && (blob.contains("[R]") || blob.contains("[L]")) {
            return .handheld
        }
        return .unknown
    }

    static func detect(rawLines: [String]) -> PrintoutFormatDetectionResult {
        detect(lines: rawLines)
    }

    static func parse(lines: [String], photoIndex: Int) throws -> PrintoutResult {
        switch detect(lines: lines) {
        case .desktop:
            return DesktopFormatParser.parse(lines: lines, photoIndex: photoIndex)
        case .handheld:
            return HandheldFormatParser.parse(lines: lines, photoIndex: photoIndex)
        case .unknown:
            throw OCRService.OCRError.unrecognizedFormat
        }
    }
}
