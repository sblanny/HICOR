import XCTest
import UIKit
@testable import HICOR

/// End-to-end tests that exercise the full ROI pipeline (with the real ML
/// Kit recognizer) against fixture JPEGs captured from the iPhone. Each
/// fixture has a sibling JSON listing the 24 expected reading values; the
/// test asserts either full match or the expected `incompleteCells` throw.
final class ROIPipelineFixtureTests: XCTestCase {

    struct Expected: Decodable {
        struct Section: Decodable {
            let r1: Reading
            let r2: Reading
            let r3: Reading
            let avg: Reading
        }
        struct Reading: Decodable {
            let sph: String
            let cyl: String
            let ax: String
        }
        struct ExpectedBlock: Decodable {
            let right: Section
            let left: Section
        }
        let expected: ExpectedBlock?
        let shouldFail: Bool
    }

    private let bundle = Bundle(for: ROIPipelineFixtureTests.self)

    private func fixtureURLs(in subdir: String) throws -> [URL] {
        let resourceURL = bundle.url(forResource: "Images/grk6000/\(subdir)", withExtension: nil)
        guard let resourceURL else {
            throw XCTSkip("fixture subdir not bundled yet: \(subdir)")
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension.lowercased() == "jpg" }.sorted { $0.path < $1.path }
    }

    private func runPipeline(on jpegURL: URL) async throws -> ExtractedText {
        guard let data = try? Data(contentsOf: jpegURL),
              let image = UIImage(data: data) else {
            throw XCTSkip("unable to load \(jpegURL.lastPathComponent)")
        }
        let extractor = ROIPipelineExtractor()
        return try await extractor.extractText(from: image)
    }

    private func assertMatches(text: ExtractedText, expected: Expected.ExpectedBlock, file: StaticString = #file, line: UInt = #line) {
        let rowBased = text.rowBased
        func format(_ r: Expected.Reading, avg: Bool) -> String {
            let prefix = avg ? "AVG " : ""
            return "\(prefix)\(r.sph) \(r.cyl) \(r.ax)"
        }

        let expectedLines: [String] = [
            "[R]",
            format(expected.right.r1, avg: false),
            format(expected.right.r2, avg: false),
            format(expected.right.r3, avg: false),
            format(expected.right.avg, avg: true),
            "[L]",
            format(expected.left.r1, avg: false),
            format(expected.left.r2, avg: false),
            format(expected.left.r3, avg: false),
            format(expected.left.avg, avg: true)
        ]
        for expected in expectedLines {
            XCTAssertTrue(rowBased.contains(expected),
                          "missing expected line: \(expected) in \(rowBased)",
                          file: file, line: line)
        }
    }

    private func processSubdir(_ subdir: String, shouldFail: Bool) async throws {
        let urls = try fixtureURLs(in: subdir)
        if urls.isEmpty {
            throw XCTSkip("no fixtures in \(subdir) yet — add real captures per README")
        }
        for url in urls {
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            guard let jsonData = try? Data(contentsOf: jsonURL) else {
                XCTFail("missing JSON for \(url.lastPathComponent)")
                continue
            }
            let expected = try JSONDecoder().decode(Expected.self, from: jsonData)
            do {
                let text = try await runPipeline(on: url)
                if shouldFail {
                    XCTFail("\(url.lastPathComponent): expected incompleteCells but pipeline succeeded")
                    continue
                }
                guard let block = expected.expected else {
                    XCTFail("\(url.lastPathComponent): JSON missing expected block"); continue
                }
                assertMatches(text: text, expected: block)
            } catch OCRService.OCRError.incompleteCells {
                if !shouldFail {
                    XCTFail("\(url.lastPathComponent): unexpected incompleteCells")
                }
            } catch {
                XCTFail("\(url.lastPathComponent): unexpected error \(error)")
            }
        }
    }

    func testDimGoodFraming() async throws {
        try await processSubdir("dim_good_framing", shouldFail: false)
    }

    func testDimTilted() async throws {
        try await processSubdir("dim_tilted", shouldFail: false)
    }

    func testBrightGoodFraming() async throws {
        try await processSubdir("bright_good_framing", shouldFail: false)
    }

    func testDimPoorFraming() async throws {
        try await processSubdir("dim_poor_framing", shouldFail: true)
    }
}
