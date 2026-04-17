import XCTest
@testable import HICOR

final class ParseScorerTests: XCTestCase {

    private func extraction(lines: [String], boxes: [TextBox] = [], variant: PreprocessingVariant = .standard) -> ExtractedText {
        ExtractedText(rowBased: lines, columnBased: [], preprocessedImageData: nil,
                      boxes: boxes, revisionUsed: 3, variant: variant)
    }

    func testScoreOfNilResultIsLow() {
        let s = ParseScorer.score(result: nil, extraction: extraction(lines: []), reconstruction: .row)
        XCTAssertEqual(s.totalScore, 0.0, accuracy: 0.001)
        XCTAssertEqual(s.validReadingCount, 0)
    }

    func testScoreRewardsMoreReadings() {
        let few = PrintoutResult.stubWithReadings(rightCount: 1, leftCount: 1)
        let many = PrintoutResult.stubWithReadings(rightCount: 8, leftCount: 8)
        let ext = extraction(lines: ["[R]", "[L]", "*"])
        let sFew = ParseScorer.score(result: few, extraction: ext, reconstruction: .row)
        let sMany = ParseScorer.score(result: many, extraction: ext, reconstruction: .row)
        XCTAssertLessThan(sFew.totalScore, sMany.totalScore)
    }

    func testScoreRewardsSectionCompleteness() {
        let oneEye = PrintoutResult.stubWithReadings(rightCount: 5, leftCount: 0)
        let bothEyes = PrintoutResult.stubWithReadings(rightCount: 3, leftCount: 3)
        let ext = extraction(lines: ["[R]", "[L]", "*"])
        let sOne = ParseScorer.score(result: oneEye, extraction: ext, reconstruction: .row)
        let sBoth = ParseScorer.score(result: bothEyes, extraction: ext, reconstruction: .row)
        XCTAssertGreaterThan(sBoth.totalScore, sOne.totalScore)
    }

    func testScoreRewardsMarkerContinuity() {
        let r = PrintoutResult.stubWithReadings(rightCount: 3, leftCount: 3)
        let withMarkers = extraction(lines: ["[R]", "reading", "[L]", "reading", "*"])
        let withoutMarkers = extraction(lines: ["reading", "reading"])
        XCTAssertGreaterThan(
            ParseScorer.score(result: r, extraction: withMarkers, reconstruction: .row).totalScore,
            ParseScorer.score(result: r, extraction: withoutMarkers, reconstruction: .row).totalScore
        )
    }

    func testAxisMatchIsTokenNotSubstring() {
        let matchingBox = TextBox(midX: 0.1, midY: 0.5, minX: 0.05, height: 0.04, text: "90", confidence: 0.95)
        let falsePositiveBox = TextBox(midX: 0.5, midY: 0.5, minX: 0.45, height: 0.04, text: "190", confidence: 0.10)

        let reading = RawReading(id: UUID(), sph: -2.00, cyl: -0.25, ax: 90, eye: .right, sourcePhotoIndex: 0)
        let eye = EyeReading(
            id: UUID(), eye: .right, readings: [reading],
            machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil,
            sourcePhotoIndex: 0, machineType: .handheld
        )
        let printout = PrintoutResult(
            rightEye: eye, leftEye: nil, pd: nil,
            machineType: .handheld, sourcePhotoIndex: 0, rawText: "",
            handheldStarConfidenceRight: nil, handheldStarConfidenceLeft: nil
        )
        let ext = ExtractedText(
            rowBased: ["90", "190"], columnBased: [],
            preprocessedImageData: nil, boxes: [matchingBox, falsePositiveBox],
            revisionUsed: 3, variant: .standard
        )

        let score = ParseScorer.score(result: printout, extraction: ext, reconstruction: .row)
        XCTAssertEqual(score.avgConfidence, 0.95, accuracy: 0.001)
    }
}

extension PrintoutResult {
    static func stubWithReadings(rightCount: Int, leftCount: Int) -> PrintoutResult {
        let rightReadings = (0..<rightCount).map { _ in
            RawReading(id: UUID(), sph: -2.00, cyl: -0.25, ax: 90, eye: .right, sourcePhotoIndex: 0)
        }
        let leftReadings = (0..<leftCount).map { _ in
            RawReading(id: UUID(), sph: -2.00, cyl: -0.25, ax: 90, eye: .left, sourcePhotoIndex: 0)
        }
        return PrintoutResult(
            rightEye: rightCount > 0 ? EyeReading(
                id: UUID(), eye: .right, readings: rightReadings,
                machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil,
                sourcePhotoIndex: 0, machineType: .handheld
            ) : nil,
            leftEye: leftCount > 0 ? EyeReading(
                id: UUID(), eye: .left, readings: leftReadings,
                machineAvgSPH: nil, machineAvgCYL: nil, machineAvgAX: nil,
                sourcePhotoIndex: 0, machineType: .handheld
            ) : nil,
            pd: nil, machineType: .handheld, sourcePhotoIndex: 0, rawText: "",
            handheldStarConfidenceRight: nil, handheldStarConfidenceLeft: nil
        )
    }
}
