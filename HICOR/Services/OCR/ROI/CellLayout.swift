import CoreGraphics

struct CellLayout {

    /// Hardcoded layout for the GRK-6000 desktop printout. The grid is
    /// expressed entirely in terms of anchor rectangles provided at call
    /// time — no fixed pixel offsets — so the layout self-calibrates per
    /// capture.
    static let grk6000Desktop = CellLayout()

    /// Returns 24 CellROI values (12 per eye) from an Anchors set:
    ///   - column X is centered on the corresponding header anchor
    ///   - row Y is interpolated between the section's SPH-header baseline
    ///     and the section's AVG anchor, divided into 4 equal rows (r1, r2,
    ///     r3, avg). Column header anchors (SPH/CYL/AX) can drift in Y
    ///     across a row on tilted prints; we use their average midY as the
    ///     header baseline.
    func cells(given anchors: Anchors) -> [CellROI] {
        return buildSection(.right, anchors.right) + buildSection(.left, anchors.left)
    }

    private func buildSection(_ eye: CellROI.Eye, _ section: SectionAnchors) -> [CellROI] {
        let headers: [(CellROI.Column, CGRect)] = [
            (.sph, section.sph),
            (.cyl, section.cyl),
            (.ax,  section.ax)
        ]
        let headerMidY = (section.sph.midY + section.cyl.midY + section.ax.midY) / 3.0
        let avgMidY    = section.avg.midY

        // Four row-midYs equally spaced between headerMidY (excluded) and
        // avgMidY. r1 sits one step below the header, r2 two steps, r3 three
        // steps, avg four steps (== avgMidY).
        let rowStep = (avgMidY - headerMidY) / 4.0
        let rowMidYs: [(CellROI.Row, CGFloat)] = [
            (.r1,  headerMidY + rowStep * 1.0),
            (.r2,  headerMidY + rowStep * 2.0),
            (.r3,  headerMidY + rowStep * 3.0),
            (.avg, avgMidY)
        ]

        // Cell width: 1.4× the header width (numbers need more horizontal
        // room than the 3-letter labels). Cell height: 1.2× the header
        // height. These multipliers were chosen to cover the printed data
        // comfortably with ~10% margin that CellROIExtractor then pads.
        var cells: [CellROI] = []
        for (column, header) in headers {
            let cellW = header.width * 1.4
            let cellH = header.height * 1.2
            for (row, midY) in rowMidYs {
                let rect = CGRect(
                    x: header.midX - cellW / 2.0,
                    y: midY - cellH / 2.0,
                    width: cellW,
                    height: cellH
                )
                cells.append(CellROI(eye: eye, column: column, row: row, rect: rect))
            }
        }
        return cells
    }
}
