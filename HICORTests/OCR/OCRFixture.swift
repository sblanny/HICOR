import Foundation

enum OCRFixture {
    static func load(_ name: String) -> [String] {
        let bundle = Bundle(for: OCRFixtureMarker.self)
        guard let url = bundle.url(forResource: name, withExtension: "txt") else {
            fatalError("Missing OCR fixture file: \(name).txt — confirm it is bundled with the HICORTests target.")
        }
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

private final class OCRFixtureMarker {}
