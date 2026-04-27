import SwiftUI
import UIKit

struct AnalysisPlaceholderView: View {
    let patientNumber: String
    let sessionContext: SessionContext
    /// Each element is one printout group: the photos the operator marked
    /// as "same sheet." Consensus runs within a group, never across.
    let printouts: [[Data]]
    let pd: Double
    let pdManualEntry: Bool
    /// Invoked when a specific printout is missing cells and the operator
    /// chose to add another photo to that printout. The int is the index
    /// into `printouts` (== display number − 1). Caller reactivates that
    /// printout in its capture state and dismisses this view.
    var onReactivatePrintout: ((Int) -> Void)? = nil
    /// Invoked when the operator taps "Capture another printout" on
    /// DisagreementReviewView. Caller pops this view off the navigation
    /// stack so the operator lands back on PhotoCaptureView with their
    /// existing printouts intact.
    var onReturnToCapture: (() -> Void)? = nil

    @Environment(OCRService.self) private var ocr
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .running
    @State private var alertState: AlertState?
    @State private var navigation: NavigationPayload?
    @State private var disagreement: DisagreementPayload?
    @State private var debugSnapshot: OCRDebugSnapshot?
    @State private var showDebugSheet: Bool = false
    @State private var presentAnalysis: Bool = false
    @State private var presentDisagreement: Bool = false

    private enum Phase {
        case running
        case awaitingDecision
        case advancing
    }

    private enum AlertState: Identifiable {
        case error(message: String, snapshot: OCRDebugSnapshot?)
        case printoutMissingCells(printoutIndex: Int, cells: [String])

        var id: String {
            switch self {
            case .error: return "error"
            case .printoutMissingCells(let idx, _): return "missing-\(idx)"
            }
        }
    }

    private struct NavigationPayload {
        let refraction: PatientRefraction
        let results: [PrintoutResult]
        let droppedOutliers: [ConsistencyValidator.DroppedReading]
        let outcome: PrescriptionCalculationOutcome
    }

    private struct DisagreementPayload {
        let mode: DisagreementReviewView.Mode
        let results: [PrintoutResult]
    }

    private var allPhotosFlat: [Data] { printouts.flatMap { $0 } }

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
            case .printoutMissingCells(let printoutIndex, let cells):
                return Alert(
                    title: Text("Printout \(printoutIndex + 1) needs another photo"),
                    message: Text(Self.missingCellsMessage(cells: cells)),
                    primaryButton: .default(Text("Add photo to Printout \(printoutIndex + 1)")) {
                        onReactivatePrintout?(printoutIndex)
                        dismiss()
                    },
                    secondaryButton: .cancel(Text("Back")) { dismiss() }
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
        .navigationDestination(isPresented: $presentDisagreement) {
            if let payload = disagreement {
                DisagreementReviewView(
                    mode: payload.mode,
                    results: payload.results,
                    onAddAnother: {
                        // dismiss() captured here pops only the topmost
                        // navigation destination (DisagreementReviewView),
                        // leaving the operator stranded on this view's
                        // spinner. The closure was passed down from
                        // PhotoCaptureView and toggles its destination
                        // binding directly — popping AnalysisPlaceholder
                        // View pops DisagreementReviewView above it too.
                        onReturnToCapture?()
                    },
                    onStartOver: {
                        NotificationCenter.default.post(name: .hicorReturnToPatientEntry, object: nil)
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Text("Navigation error")
                        .font(.headline)
                    Text("The disagreement data was lost. Please retake the photo.")
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
        OCRLog.logger.info("OCR nav: runOCR started printouts=\(printouts.count) photos=\(printouts.reduce(0){$0+$1.count})")
        let groupImages: [[UIImage]] = printouts.map { $0.compactMap { UIImage(data: $0) } }
        guard groupImages.contains(where: { !$0.isEmpty }) else {
            OCRLog.logger.error("OCR nav: no decodable images across any printout")
            presentError("No usable photo was captured.", snapshot: nil)
            return
        }

        let perPrintout = await ocr.processPrintoutsWithConsensus(groupImages)

        // Aggregate debug entries from every printout's consensus snapshot
        // so #if DEBUG operators see the full picture of what was read.
        let aggregatedEntries = perPrintout.flatMap(\.debugSnapshot.entries)
        let aggregatedError = perPrintout.compactMap { $0.debugSnapshot.overallError.isEmpty ? nil : $0.debugSnapshot.overallError }.joined(separator: "; ")
        debugSnapshot = OCRDebugSnapshot(entries: aggregatedEntries, overallError: aggregatedError)

        for (pIdx, result) in perPrintout.enumerated() {
            for dis in result.disagreements {
                let summary = dis.votes.map { "\($0.value)×\($0.photoIndices.count)" }.joined(separator: ", ")
                OCRLog.logger.info("OCR nav: printout=\(pIdx, privacy: .public) disagreement cell=\(dis.cellLabel, privacy: .public) votes=\(summary, privacy: .public)")
            }
        }

        // First printout with unresolved cells — block here and ask for
        // another photo OF THAT PRINTOUT. Different printouts are
        // independent captures; fixing one shouldn't force the operator
        // to recapture the rest.
        if let firstMissing = perPrintout.enumerated().first(where: { !$0.element.missingCells.isEmpty }) {
            let idx = firstMissing.offset
            let cells = firstMissing.element.missingCells
            OCRLog.logger.error("OCR nav: printout=\(idx, privacy: .public) missing=\(cells.joined(separator: ","), privacy: .public)")
            await persistFailure(snapshot: debugSnapshot ?? OCRDebugSnapshot(entries: [], overallError: ""))
            alertState = .printoutMissingCells(printoutIndex: idx, cells: cells)
            phase = .awaitingDecision
            return
        }

        // Flatten: one PrintoutResult per printout group. Each group's
        // `perImage` holds identical merged results across its photos —
        // take the first, tagged with its group index so downstream logs
        // and audit trails refer to the printout, not the photo.
        var results: [PrintoutResult] = []
        for (idx, group) in perPrintout.enumerated() {
            guard let first = group.perImage.first else { continue }
            results.append(PrintoutResult(
                rightEye: first.rightEye,
                leftEye: first.leftEye,
                pd: first.pd,
                machineType: first.machineType,
                sourcePhotoIndex: idx,
                rawText: first.rawText,
                handheldStarConfidenceRight: first.handheldStarConfidenceRight,
                handheldStarConfidenceLeft: first.handheldStarConfidenceLeft
            ))
        }

        guard !results.isEmpty else {
            OCRLog.logger.error("OCR nav: consensus produced no PrintoutResults despite no missing cells")
            await persistFailure(snapshot: debugSnapshot ?? OCRDebugSnapshot(entries: [], overallError: ""))
            presentError("The captured photos couldn't be parsed. Please retake the photo.", snapshot: debugSnapshot)
            return
        }

        let detectedPD = results.compactMap(\.pd).first
        let finalPD = detectedPD ?? pd
        let finalPDManualEntry = (detectedPD == nil) ? true : false

        let encoded = (try? JSONEncoder().encode(results)) ?? Data()
        let refraction = PatientRefraction(
            patientNumber: patientNumber,
            sessionDate: Date(),
            sessionLocation: sessionContext.location,
            pd: finalPD,
            pdManualEntry: finalPDManualEntry,
            rawReadingsData: encoded,
            photoData: allPhotosFlat
        )

        let validator = ConsistencyValidator()
        let outcome = validator.validate(results)
        OCRLog.logger.info("OCR nav: consistency=\(String(describing: outcome), privacy: .public)")

        switch outcome {
        case .consistent(let droppedOutliers):
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
            disagreement = DisagreementPayload(
                mode: .addAnother(reason: reason, currentCount: currentCount),
                results: results
            )
            presentDisagreement = true
        case .inconsistentEscalate(let reason):
            phase = .awaitingDecision
            disagreement = DisagreementPayload(
                mode: .escalate(reason: reason),
                results: results
            )
            presentDisagreement = true
        }
    }

    private func presentError(_ message: String, snapshot: OCRDebugSnapshot?) {
        debugSnapshot = snapshot
        phase = .awaitingDecision
        alertState = .error(message: message, snapshot: snapshot)
    }

    private func persistFailure(snapshot: OCRDebugSnapshot) async {
        let encoded = (try? JSONEncoder().encode(snapshot.strippingImages())) ?? Data()
        let failureRecord = PatientRefraction(
            patientNumber: patientNumber,
            sessionDate: Date(),
            sessionLocation: sessionContext.location,
            pd: pd,
            pdManualEntry: pdManualEntry,
            rawReadingsData: encoded,
            photoData: allPhotosFlat
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

    /// Human-readable cell list for the missing-cells alert. Limits to 3
    /// labels to keep the alert legible; the rest collapse to "+N more."
    static func missingCellsMessage(cells: [String]) -> String {
        let labels = cells.prefix(3).joined(separator: ", ")
        let suffix = cells.count > 3 ? ", plus \(cells.count - 3) more" : ""
        return "Missing: \(labels)\(suffix). Take another photo of the same printout to fill in the gap."
    }
}
