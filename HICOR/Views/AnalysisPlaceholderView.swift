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
        case hardBlock(message: String)
        case overridable(message: String)
        case error(message: String, snapshot: OCRDebugSnapshot?)

        var id: String {
            switch self {
            case .hardBlock:   return "hardBlock"
            case .overridable: return "overridable"
            case .error:       return "error"
            }
        }
    }

    private struct NavigationPayload {
        let refraction: PatientRefraction
        let results: [PrintoutResult]
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
            case .hardBlock(let message):
                return Alert(
                    title: Text("Cannot continue"),
                    message: Text(message),
                    dismissButton: .default(Text("Back to Photo")) { dismiss() }
                )
            case .overridable(let message):
                return Alert(
                    title: Text("Inconsistent readings"),
                    message: Text(message),
                    primaryButton: .default(Text("Override and Continue")) {
                        if let payload = navigation {
                            payload.refraction.consistencyWarningOverridden = true
                            print("=== OCR nav: override accepted, navigating to PrescriptionAnalysisView ===")
                            phase = .advancing
                            presentAnalysis = true
                        } else {
                            print("=== OCR nav: override tapped but navigation payload missing — dismissing ===")
                            dismiss()
                        }
                    },
                    secondaryButton: .cancel(Text("Back to Photo")) { dismiss() }
                )
            case .error(let message, let snapshot):
                if snapshot != nil {
                    return Alert(
                        title: Text("Could not read printout"),
                        message: Text(message),
                        primaryButton: .default(Text("Show Debug Info")) {
                            showDebugSheet = true
                        },
                        secondaryButton: .cancel(Text("Back to Photo")) { dismiss() }
                    )
                } else {
                    return Alert(
                        title: Text("Could not read printout"),
                        message: Text(message),
                        dismissButton: .default(Text("Back to Photo")) { dismiss() }
                    )
                }
            }
        }
        .sheet(isPresented: $showDebugSheet) {
            if let snapshot = debugSnapshot {
                OCRDebugView(snapshot: snapshot) {
                    showDebugSheet = false
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $presentAnalysis) {
            if let payload = navigation {
                PrescriptionAnalysisView(
                    refraction: payload.refraction,
                    results: payload.results
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
        print("=== OCR nav: runOCR started (\(photos.count) photos) ===")
        let images = photos.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            print("=== OCR nav: no decodable images — presenting error alert ===")
            presentError("No usable photo was captured.", snapshot: nil)
            return
        }

        let batch = await ocr.processImages(images)
        debugSnapshot = batch.debugSnapshot

        for entry in batch.debugSnapshot.entries {
            print("=== OCR Debug: Photo \(entry.photoIndex + 1) ===")
            print("Winning variant: \(entry.winningVariant ?? "none") revision=\(entry.revisionUsed.map(String.init) ?? "n/a") strategy=\(entry.chosenStrategy)")
            if let err = entry.parseError { print("Parse error: \(err)") }
            print("===")
        }

        if let err = batch.overallError, batch.successfulResults.isEmpty {
            let baseMessage = humanReadable(err)
            print("=== OCR nav: OCR/parse failure — presenting error alert (error=\(err)) ===")
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
        navigation = NavigationPayload(refraction: refraction, results: results)
        print("=== OCR nav: consistency result = \(outcome.result), message = \(outcome.message ?? "nil") ===")

        switch outcome.result {
        case .ok:
            print("=== OCR nav: OK — navigating to PrescriptionAnalysisView ===")
            phase = .advancing
            presentAnalysis = true
        case .warningOverridable:
            print("=== OCR nav: warningOverridable — presenting override alert ===")
            phase = .awaitingDecision
            alertState = .overridable(message: outcome.message ?? "Readings are inconsistent. Verify before continuing.")
        case .hardBlock:
            print("=== OCR nav: hardBlock — presenting block alert ===")
            phase = .awaitingDecision
            alertState = .hardBlock(message: outcome.message ?? "Readings cannot be reconciled. Retake the photo.")
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
            }
        }
        return error.localizedDescription
    }
}
