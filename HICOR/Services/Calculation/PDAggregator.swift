import Foundation

// PD aggregation per MIKE_RX_PROCEDURE.md §9. Mean across the printouts
// that recorded a PD; if max − min > 5 mm the readings disagree enough
// that the volunteer should fall back to a manual measurement.
enum PDAggregator {

    struct Aggregate: Equatable {
        let pd: Double?
        let sourceCount: Int
        let spreadMm: Double
        let requiresManualMeasurement: Bool
    }

    static func aggregate(pds: [Double]) -> Aggregate {
        guard !pds.isEmpty else {
            return Aggregate(pd: nil, sourceCount: 0, spreadMm: 0.0, requiresManualMeasurement: false)
        }
        let mean = pds.reduce(0, +) / Double(pds.count)
        let spread = (pds.max() ?? 0) - (pds.min() ?? 0)
        let requiresManual = spread > Constants.pdMaxSpreadBeforeManual
        return Aggregate(
            pd: mean,
            sourceCount: pds.count,
            spreadMm: spread,
            requiresManualMeasurement: requiresManual
        )
    }
}
