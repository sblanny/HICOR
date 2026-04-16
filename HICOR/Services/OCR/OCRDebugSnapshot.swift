import Foundation

struct OCRDebugSnapshot: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let photoIndex: Int
        let extractedLines: [String]
        let detectedFormat: String
        let parseError: String?
    }
    let entries: [Entry]
    let overallError: String
}
