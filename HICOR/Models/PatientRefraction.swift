import Foundation
import SwiftData
import UIKit

@Model
final class PatientRefraction {
    var id: UUID
    var patientNumber: String
    var sessionDate: Date
    var sessionLocation: String
    var odSPH: Double
    var odCYL: Double
    var odAX: Int
    var osSPH: Double
    var osCYL: Double
    var osAX: Int
    var pd: Double
    var pdManualEntry: Bool
    var matchedLensOD: String
    var matchedLensOS: String
    var rawReadingsData: Data
    @Attribute(.externalStorage) var photoData: [Data]
    var consistencyWarningOverridden: Bool
    var createdAt: Date
    var deviceID: String
    var cloudKitRecordID: String?
    var syncedToCloud: Bool

    // MARK: - Phase 5 audit fields
    //
    // Populated via `apply(outcome:patientNotifiedTier2:tier0Decision:)` after
    // PrescriptionCalculator produces the final prescription. Stored so the
    // trip audit trail can answer "what did we dispense and why" after the
    // fact, independent of the raw OCR captures.
    var dispensingTier: String?
    var finalRightSource: String?
    var finalLeftSource: String?
    var acceptedReadingsJSON: Data
    var droppedOutliersJSON: Data
    var clinicalFlagsJSON: Data
    var pdSource: String?
    var pdSpread: Double
    var manualReviewRequired: Bool
    var noGlassesReason: String?
    // nil = not a Tier 2 case; true = operator confirmed notification;
    // false = Tier 2 saved without confirmation (edge case, UI gate bypassed).
    var patientNotifiedTier2: Bool?

    init(
        id: UUID = UUID(),
        patientNumber: String,
        sessionDate: Date,
        sessionLocation: String,
        odSPH: Double = 0,
        odCYL: Double = 0,
        odAX: Int = 0,
        osSPH: Double = 0,
        osCYL: Double = 0,
        osAX: Int = 0,
        pd: Double = 0,
        pdManualEntry: Bool = false,
        matchedLensOD: String = "",
        matchedLensOS: String = "",
        rawReadingsData: Data = Data(),
        photoData: [Data] = [],
        consistencyWarningOverridden: Bool = false,
        createdAt: Date = Date(),
        deviceID: String = UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
        cloudKitRecordID: String? = nil,
        syncedToCloud: Bool = false,
        dispensingTier: String? = nil,
        finalRightSource: String? = nil,
        finalLeftSource: String? = nil,
        acceptedReadingsJSON: Data = Data(),
        droppedOutliersJSON: Data = Data(),
        clinicalFlagsJSON: Data = Data(),
        pdSource: String? = nil,
        pdSpread: Double = 0,
        manualReviewRequired: Bool = false,
        noGlassesReason: String? = nil,
        patientNotifiedTier2: Bool? = nil
    ) {
        self.id = id
        self.patientNumber = patientNumber
        self.sessionDate = sessionDate
        self.sessionLocation = sessionLocation
        self.odSPH = odSPH
        self.odCYL = odCYL
        self.odAX = odAX
        self.osSPH = osSPH
        self.osCYL = osCYL
        self.osAX = osAX
        self.pd = pd
        self.pdManualEntry = pdManualEntry
        self.matchedLensOD = matchedLensOD
        self.matchedLensOS = matchedLensOS
        self.rawReadingsData = rawReadingsData
        self.photoData = photoData
        self.consistencyWarningOverridden = consistencyWarningOverridden
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.cloudKitRecordID = cloudKitRecordID
        self.syncedToCloud = syncedToCloud
        self.dispensingTier = dispensingTier
        self.finalRightSource = finalRightSource
        self.finalLeftSource = finalLeftSource
        self.acceptedReadingsJSON = acceptedReadingsJSON
        self.droppedOutliersJSON = droppedOutliersJSON
        self.clinicalFlagsJSON = clinicalFlagsJSON
        self.pdSource = pdSource
        self.pdSpread = pdSpread
        self.manualReviewRequired = manualReviewRequired
        self.noGlassesReason = noGlassesReason
        self.patientNotifiedTier2 = patientNotifiedTier2
    }

    // MARK: - Phase 5 outcome application

    // Populates the Phase 5 audit fields and copies the final rounded values
    // into the existing odSPH/odCYL/odAX/osSPH/osCYL/osAX/pd columns the rest
    // of the app already reads.
    //
    // patientNotifiedTier2:
    //   - Pass `true` when the operator confirmed notification on the Tier 2
    //     acknowledgement toggle.
    //   - Pass `false` when saving a Tier 2 case without confirmation
    //     (edge case; the UI normally blocks this).
    //   - Pass `nil` for non-Tier-2 outcomes — the stored field stays nil so
    //     audit readers can distinguish "not applicable" from "not confirmed".
    //
    // tier0Decision:
    //   - Pass `.noGlassesNeeded` when the operator completed the symptom
    //     check and reported no symptoms; we record "no symptoms" in
    //     `noGlassesReason`.
    //   - Any other value leaves `noGlassesReason` nil.
    func apply(
        outcome: PrescriptionCalculationOutcome,
        patientNotifiedTier2: Bool?,
        tier0Decision: Tier0SymptomCheck.Decision?
    ) {
        self.dispensingTier = outcome.overallTier.rawValue
        self.manualReviewRequired = outcome.requiresManualReview

        if let right = outcome.rightEye {
            self.odSPH = right.sph
            self.odCYL = right.cyl
            self.odAX = right.ax
            self.finalRightSource = right.source.rawValue
        }
        if let left = outcome.leftEye {
            self.osSPH = left.sph
            self.osCYL = left.cyl
            self.osAX = left.ax
            self.finalLeftSource = left.source.rawValue
        }

        var accepted: [RawReading] = []
        if let r = outcome.rightEye { accepted.append(contentsOf: r.acceptedReadings) }
        if let l = outcome.leftEye  { accepted.append(contentsOf: l.acceptedReadings) }
        self.acceptedReadingsJSON = (try? JSONEncoder().encode(accepted)) ?? Data()

        var allDropped: [ConsistencyValidator.DroppedReading] = outcome.upstreamDroppedOutliers
        if let r = outcome.rightEye { allDropped.append(contentsOf: r.phase5DroppedOutliers) }
        if let l = outcome.leftEye  { allDropped.append(contentsOf: l.phase5DroppedOutliers) }
        self.droppedOutliersJSON = (try? JSONEncoder().encode(allDropped)) ?? Data()

        self.clinicalFlagsJSON = (try? JSONEncoder().encode(outcome.clinicalFlags)) ?? Data()

        if let pdValue = outcome.pd.pd {
            self.pd = pdValue
            self.pdSpread = outcome.pd.spreadMm
            self.pdSource = outcome.pd.requiresManualMeasurement
                ? "aggregate-manual-recommended"
                : "aggregate"
        }

        // Tier 2 — record operator acknowledgement state.
        // For other tiers, leave nil so audit can distinguish "not applicable"
        // from "applicable but not confirmed."
        if outcome.overallTier == .tier2StretchWithNotification {
            self.patientNotifiedTier2 = patientNotifiedTier2
        } else {
            self.patientNotifiedTier2 = nil
        }

        // Tier 0 "no symptoms" short-circuit.
        if outcome.overallTier == .tier0NoGlassesNeeded,
           tier0Decision == .noGlassesNeeded {
            self.noGlassesReason = "no symptoms"
        } else {
            self.noGlassesReason = nil
        }
    }
}
