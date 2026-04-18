import CoreGraphics

struct SectionAnchors: Equatable {
    let eyeMarker: CGRect   // <R>/[R] or <L>/[L]
    let sph: CGRect
    let cyl: CGRect
    let ax: CGRect
    let avg: CGRect
}

struct Anchors: Equatable {
    let right: SectionAnchors
    let left: SectionAnchors
}

struct CellROI: Equatable, Hashable {

    enum Eye: String, Equatable, Hashable { case right, left }
    enum Column: String, Equatable, Hashable { case sph, cyl, ax }
    enum Row: String, Equatable, Hashable { case r1, r2, r3, avg }

    let eye: Eye
    let column: Column
    let row: Row
    let rect: CGRect

    // Equality and hashing key only on (eye, column, row) so the orchestrator
    // can look up a cell by identity with a placeholder rect.
    static func == (lhs: CellROI, rhs: CellROI) -> Bool {
        lhs.eye == rhs.eye && lhs.column == rhs.column && lhs.row == rhs.row
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(eye)
        hasher.combine(column)
        hasher.combine(row)
    }
}
