import Foundation

struct OCRDebugSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let photoIndex: Int
        let rowBasedLines: [String]
        let rowBasedFormat: String
        let columnBasedLines: [String]
        let columnBasedFormat: String
        let chosenStrategy: String
        let parseError: String?
        let preprocessedImageData: Data?
        let variantScores: [VariantScore]?
        let revisionUsed: Int?
        let winningVariant: String?

        init(
            photoIndex: Int,
            rowBasedLines: [String],
            rowBasedFormat: String,
            columnBasedLines: [String],
            columnBasedFormat: String,
            chosenStrategy: String,
            parseError: String?,
            preprocessedImageData: Data? = nil,
            variantScores: [VariantScore]? = nil,
            revisionUsed: Int? = nil,
            winningVariant: String? = nil
        ) {
            self.photoIndex = photoIndex
            self.rowBasedLines = rowBasedLines
            self.rowBasedFormat = rowBasedFormat
            self.columnBasedLines = columnBasedLines
            self.columnBasedFormat = columnBasedFormat
            self.chosenStrategy = chosenStrategy
            self.parseError = parseError
            self.preprocessedImageData = preprocessedImageData
            self.variantScores = variantScores
            self.revisionUsed = revisionUsed
            self.winningVariant = winningVariant
        }
    }
    let entries: [Entry]
    let overallError: String

    /// Returns a copy with per-entry preprocessed JPEGs removed. Use before
    /// persisting to CloudKit — the CKRecord field limit is ~1 MB, and
    /// embedded JPEGs easily blow past that.
    func strippingImages() -> OCRDebugSnapshot {
        let stripped = entries.map { e in
            Entry(
                photoIndex: e.photoIndex,
                rowBasedLines: e.rowBasedLines,
                rowBasedFormat: e.rowBasedFormat,
                columnBasedLines: e.columnBasedLines,
                columnBasedFormat: e.columnBasedFormat,
                chosenStrategy: e.chosenStrategy,
                parseError: e.parseError,
                preprocessedImageData: nil,
                variantScores: e.variantScores,
                revisionUsed: e.revisionUsed,
                winningVariant: e.winningVariant
            )
        }
        return OCRDebugSnapshot(entries: stripped, overallError: overallError)
    }
}
