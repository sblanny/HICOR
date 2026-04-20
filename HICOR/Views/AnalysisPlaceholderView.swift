import SwiftUI
import UIKit

struct AnalysisPlaceholderView: View {
    let patientNumber: String
    let sessionContext: SessionContext
    let photos: [Data]
    let pd: Double
    let pdManualEntry: Bool

    @Environment(OCRService.self) private var ocr
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .running
    @State private var alertState: AlertState?
    @State private var navigation: NavigationPayload?
    @State private var debugSnapshot: OCRDebugSnapshot?
    @State private var showDebugSheet: Bool = false
    @State private var presentAnalysis: Bool = false

    private enum Phase {
        case running
        case awaitingDecision
        case advancing
    }

    // Stacking multiple `.alert(item:)` modifiers on the same view is a known
    // SwiftUI footgun — only the outermost reliably presents, the others may
    // silently fail. One alert state, one modifier, switch on the case.
    private enum AlertState: Identifiable {
        case addPhoto(message: String)
        case escalate(message: String)
        case error(message: String, snapshot: OCRDebugSnapshot?)

        var id: String {
            switch self {
            case .addPhoto: return "addPhoto"
            case .escalate: return "escalate"
            case .error:    return "error"
            }
        }
    }

    private struct NavigationPayload {
        let refraction: PatientRefraction
        let results: [PrintoutResult]
        let droppedOutliers: [ConsistencyValidator.DroppedReading]
        let outcome: PrescriptionCalculationOutcome
    }

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.extraLarge)
            Text("Analyzing prescription…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarBackButtonHidden(true)
        .task(id: phase == .running ? "run" : "idle") {
            guard phase == .running else { return }
            await runOCR()
        }
        .alert(item: $alertState) { state in
            switch state {
            case .addPhoto(let message):
                return Alert(
                    title: Text("Readings don't agree"),
                    message: Text(message),
                    dismissButton: .default(Text("Add another printout")) { dismiss() }
                )
            case .escalate(let message):
                return Alert(
                    title: Text("Consult team leader"),
                    message: Text(message),
                    dismissButton: .default(Text("Start over")) { dismiss() }
                )
            case .error(let message, let snapshot):
                #if DEBUG
                if snapshot != nil {
                    return Alert(
                        title: Text("Could not read printout"),
                        message: Text(message),
                        primaryButton: .default(Text("Show Debug Info")) {
                            showDebugSheet = true
                        },
                        secondaryButton: .cancel(Text("Back to Photo")) { dismiss() }
                    )
                }
                #endif
                _ = snapshot
                return Alert(
                    title: Text("Could not read printout"),
                    message: Text(message),
                    dismissButton: .default(Text("Back to Photo")) { dismiss() }
                )
            }
        }
        #if DEBUG
        .sheet(isPresented: $showDebugSheet) {
            if let snapshot = debugSnapshot {
                OCRDebugView(snapshot: snapshot) {
                    showDebugSheet = false
                    dismiss()
                }
            }
        }
        #endif
        .navigationDestination(isPresented: $presentAnalysis) {
            if let payload = navigation {
                PrescriptionAnalysisView(
                    refraction: payload.refraction,
                    results: payload.results,
                    droppedOutliers: payload.droppedOutliers,
                    finalOutcome: payload.outcome
                )
            } else {
                // Defensive fallback: binding flipped to true but payload is nil.
                // Show an explicit error rather than a blank screen.
                VStack(spacing: 12) {
                    Text("Navigation error")
                        .font(.headline)
                    Text("The prescription analysis data was lost. Please retake the photo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Back to Photo") { dismiss() }
                }
                .padding()
            }
        }
    }

    @MainActor
    private func runOCR() async {
        OCRLog.logger.info("OCR nav: runOCR started photos=\(photos.count)")
        let images = photos.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            OCRLog.logger.error("OCR nav: no decodable images")
            presentError("No usable photo was captured.", snapshot: nil)
            return
        }

        let batch = await ocr.processImages(images)
        debugSnapshot = batch.debugSnapshot

        if let err = batch.overallError, batch.successfulResults.isEmpty {
            let baseMessage = humanReadable(err)
            OCRLog.logger.error("OCR nav: parse failure error=\(String(describing: err), privacy: .public)")
            await persistFailure(snapshot: batch.debugSnapshot)
            presentError(baseMessage, snapshot: batch.debugSnapshot)
            return
        }

        let results = batch.successfulResults
        let detectedPD = results.compactMap(\.pd).first
        let finalPD = detectedPD ?? pd
        let finalPDManualEntry = (detectedPD == nil) ? true : false

        let encoded = (try? JSONEncoder().encode(results)) ?? Data()
        let refraction = PatientRefraction(
            patientNumber: patientNumber,
            sessionDate: sessionContext.date,
            sessionLocation: sessionContext.location,
            pd: finalPD,
            pdManualEntry: finalPDManualEntry,
            rawReadingsData: encoded,
            photoData: photos
        )

        let validator = ConsistencyValidator()
        let outcome = validator.validate(results)
        OCRLog.logger.info("OCR nav: consistency=\(String(describing: outcome), privacy: .public)")

        switch outcome {
        case .consistent(let droppedOutliers):
            // Phase 5: compute the final prescription only on `.consistent`.
            // `.inconsistentAddPhoto` / `.inconsistentEscalate` short-circuit to
            // the operator alerts below — no calculator invocation on those paths.
            let finalOutcome = PrescriptionCalculator.calculate(
                printouts: results,
                upstreamDroppedOutliers: droppedOutliers
            )
            navigation = NavigationPayload(
                refraction: refraction,
                results: results,
                droppedOutliers: droppedOutliers,
                outcome: finalOutcome
            )
            phase = .advancing
            presentAnalysis = true
        case .inconsistentAddPhoto(let reason, let currentCount):
            phase = .awaitingDecision
            alertState = .addPhoto(message: "\(reason). You have \(currentCount) of up to \(Constants.maxPhotosAllowed) printouts — please capture another.")
        case .inconsistentEscalate(let reason):
            phase = .awaitingDecision
            alertState = .escalate(message: "Five printouts captured but readings still don't agree (\(reason)). Please consult your team leader before proceeding.")
        }
    }

    private func presentError(_ message: String, snapshot: OCRDebugSnapshot?) {
        debugSnapshot = snapshot
        phase = .awaitingDecision
        alertState = .error(message: message, snapshot: snapshot)
    }

    private func persistFailure(snapshot: OCRDebugSnapshot) async {
        // rawReadingsData rides in CloudKit as rawReadingsJSON, which shares the
        // CKRecord's ~1 MB field budget. Strip embedded JPEGs before encoding.
        let encoded = (try? JSONEncoder().encode(snapshot.strippingImages())) ?? Data()
        let failureRecord = PatientRefraction(
            patientNumber: patientNumber,
            sessionDate: sessionContext.date,
            sessionLocation: sessionContext.location,
            pd: pd,
            pdManualEntry: pdManualEntry,
            rawReadingsData: encoded,
            photoData: photos
        )
        await sync.save(failureRecord)
    }

    private func humanReadable(_ error: Error) -> String {
        if let ocrError = error as? OCRService.OCRError {
            switch ocrError {
            case .noTextFound:
                return "No text was detected in the photo. Retake it with better lighting."
            case .unrecognizedFormat:
                return "The printout format was not recognized. Confirm the photo shows the autorefractor slip."
            case .insufficientReadings:
                return "Not enough valid readings were extracted. Retake the photo."
            case .incompleteCells(let missing):
                let labels = missing.prefix(3).joined(separator: ", ")
                let suffix = missing.count > 3 ? ", plus \(missing.count - 3) more" : ""
                return "Couldn't read all readings (\(labels)\(suffix)). Retake the photo with the printout well-lit and centered in the frame."
            }
        }
        return error.localizedDescription
    }
}
