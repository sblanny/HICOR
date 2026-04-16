import SwiftUI
import UIKit

struct AnalysisPlaceholderView: View {
    let patientNumber: String
    let sessionContext: SessionContext
    let photos: [Data]
    let pd: Double
    let pdManualEntry: Bool

    @Environment(OCRService.self) private var ocr
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .running
    @State private var hardBlockAlert: AlertContent?
    @State private var overridableAlert: AlertContent?
    @State private var errorAlert: AlertContent?
    @State private var navigation: NavigationPayload?

    private enum Phase {
        case running
        case awaitingDecision
        case advancing
    }

    private struct AlertContent: Identifiable {
        let id = UUID()
        let message: String
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
        .alert(item: $hardBlockAlert) { content in
            Alert(
                title: Text("Cannot continue"),
                message: Text(content.message),
                dismissButton: .default(Text("Back to Photos")) { dismiss() }
            )
        }
        .alert(item: $overridableAlert) { content in
            Alert(
                title: Text("Inconsistent readings"),
                message: Text(content.message),
                primaryButton: .default(Text("Override and Continue")) {
                    if let payload = navigation {
                        let refraction = payload.refraction
                        refraction.consistencyWarningOverridden = true
                        phase = .advancing
                    }
                },
                secondaryButton: .cancel(Text("Back to Photos")) { dismiss() }
            )
        }
        .alert(item: $errorAlert) { content in
            Alert(
                title: Text("Could not read printouts"),
                message: Text(content.message),
                dismissButton: .default(Text("Back to Photos")) { dismiss() }
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { phase == .advancing && navigation != nil },
            set: { if !$0 { phase = .awaitingDecision } }
        )) {
            if let payload = navigation {
                PrescriptionAnalysisView(
                    refraction: payload.refraction,
                    results: payload.results
                )
            }
        }
    }

    private func runOCR() async {
        let images = photos.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            errorAlert = AlertContent(message: "No usable photos were captured.")
            return
        }

        let results: [PrintoutResult]
        do {
            results = try await ocr.processImages(images)
        } catch {
            errorAlert = AlertContent(message: humanReadable(error))
            return
        }

        guard hasAnyReading(in: results) else {
            errorAlert = AlertContent(message: "No SPH/CYL/AX readings could be extracted from the photos. Retake them with better focus and lighting.")
            return
        }

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
        let outcome = validator.validate(results, photoCount: photos.count)
        navigation = NavigationPayload(refraction: refraction, results: results)

        switch outcome.result {
        case .ok:
            phase = .advancing
        case .warningOverridable:
            overridableAlert = AlertContent(message: outcome.message ?? "Readings are inconsistent. Verify before continuing.")
            phase = .awaitingDecision
        case .hardBlock:
            hardBlockAlert = AlertContent(message: outcome.message ?? "Readings cannot be reconciled. Capture additional printouts.")
            phase = .awaitingDecision
        }
    }

    private func hasAnyReading(in results: [PrintoutResult]) -> Bool {
        results.contains { $0.rightEye != nil || $0.leftEye != nil }
    }

    private func humanReadable(_ error: Error) -> String {
        if let ocrError = error as? OCRService.OCRError {
            switch ocrError {
            case .noTextFound:
                return "No text was detected in the photos. Retake them with better lighting."
            case .unrecognizedFormat:
                return "The printout format was not recognized. Confirm the photo shows the autorefractor slip."
            case .insufficientReadings:
                return "Not enough valid readings were extracted. Retake the photos."
            }
        }
        return error.localizedDescription
    }
}

