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
    }
    let entries: [Entry]
    let overallError: String
}
