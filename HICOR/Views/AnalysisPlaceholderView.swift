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
    @State private var hardBlockAlert: AlertContent?
    @State private var overridableAlert: AlertContent?
    @State private var errorAlert: ErrorAlertContent?
    @State private var navigation: NavigationPayload?
    @State private var debugSnapshot: OCRDebugSnapshot?
    @State private var showDebugSheet: Bool = false
    @State private var presentAnalysis: Bool = false

    private enum Phase {
        case running
        case awaitingDecision
        case advancing
    }

    private struct AlertContent: Identifiable {
        let id = UUID()
        let message: String
    }

    private struct ErrorAlertContent: Identifiable {
        let id = UUID()
        let message: String
        let snapshot: OCRDebugSnapshot?
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
                        payload.refraction.consistencyWarningOverridden = true
                        print("=== OCR nav: override accepted, navigating to PrescriptionAnalysisView ===")
                        phase = .advancing
                        presentAnalysis = true
                    } else {
                        print("=== OCR nav: override tapped but navigation payload missing — dismissing ===")
                        dismiss()
                    }
                },
                secondaryButton: .cancel(Text("Back to Photos")) { dismiss() }
            )
        }
        .alert(item: $errorAlert) { content in
            if content.snapshot != nil {
                return Alert(
                    title: Text("Could not read printouts"),
                    message: Text(content.message),
                    primaryButton: .default(Text("Show Debug Info")) {
                        showDebugSheet = true
                    },
                    secondaryButton: .cancel(Text("Back to Photos")) { dismiss() }
                )
            } else {
                return Alert(
                    title: Text("Could not read printouts"),
                    message: Text(content.message),
                    dismissButton: .default(Text("Back to Photos")) { dismiss() }
                )
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
                    Text("The prescription analysis data was lost. Please retake photos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Back to Photos") { dismiss() }
                }
                .padding()
            }
        }
    }

    private func runOCR() async {
        print("=== OCR nav: runOCR started (\(photos.count) photos) ===")
        let images = photos.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            print("=== OCR nav: no decodable images — presenting error alert ===")
            presentError("No usable photos were captured.", snapshot: nil)
            return
        }

        var results: [PrintoutResult] = []
        var debugEntries: [OCRDebugSnapshot.Entry] = []
        var firstError: Error?

        for (index, image) in images.enumerated() {
            let extracted: ExtractedText
            do {
                extracted = try await ocr.extractText(from: image)
            } catch {
                firstError = firstError ?? error
                logDebug(
                    photoIndex: index,
                    rowFormat: "unknown", rowLines: [],
                    columnFormat: "unknown", columnLines: [],
                    chosen: "none",
                    parseResult: "Vision extraction failed: \(error.localizedDescription)"
                )
                debugEntries.append(.init(
                    photoIndex: index,
                    rowBasedLines: [],
                    rowBasedFormat: "unknown",
                    columnBasedLines: [],
                    columnBasedFormat: "unknown",
                    chosenStrategy: "none",
                    parseError: "Vision extraction failed: \(error.localizedDescription)",
                    preprocessedImageData: nil
                ))
                continue
            }

            let rowFormat = formatName(PrintoutParser.detect(lines: extracted.rowBased))
            let columnFormat = formatName(PrintoutParser.detect(lines: extracted.columnBased))

            let rowAttempt = try? PrintoutParser.parse(lines: extracted.rowBased, photoIndex: index)
            let colAttempt = try? PrintoutParser.parse(lines: extracted.columnBased, photoIndex: index)
            let rowReadings = readingCount(rowAttempt)
            let colReadings = readingCount(colAttempt)

            let chosen: (PrintoutResult, String)?
            if rowReadings > 0, let r = rowAttempt {
                chosen = (r, "row-based")
            } else if colReadings > 0, let c = colAttempt {
                chosen = (c, "column-based")
            } else if let r = rowAttempt {
                chosen = (r, "row-based")
            } else if let c = colAttempt {
                chosen = (c, "column-based")
            } else {
                chosen = nil
            }

            if let (parsed, strategy) = chosen, parsed.rightEye != nil || parsed.leftEye != nil {
                results.append(parsed)
                let resultDesc = "OK via \(strategy) (R: \(parsed.rightEye?.readings.count ?? 0) readings, L: \(parsed.leftEye?.readings.count ?? 0) readings, PD: \(parsed.pd.map { "\(Int($0))" } ?? "nil"))"
                logDebug(
                    photoIndex: index,
                    rowFormat: rowFormat, rowLines: extracted.rowBased,
                    columnFormat: columnFormat, columnLines: extracted.columnBased,
                    chosen: strategy,
                    parseResult: resultDesc
                )
                debugEntries.append(.init(
                    photoIndex: index,
                    rowBasedLines: extracted.rowBased,
                    rowBasedFormat: rowFormat,
                    columnBasedLines: extracted.columnBased,
                    columnBasedFormat: columnFormat,
                    chosenStrategy: strategy,
                    parseError: nil,
                    preprocessedImageData: extracted.preprocessedImageData
                ))
            } else {
                let err = OCRService.OCRError.unrecognizedFormat
                firstError = firstError ?? err
                let parseError = "Both strategies failed to extract readings."
                logDebug(
                    photoIndex: index,
                    rowFormat: rowFormat, rowLines: extracted.rowBased,
                    columnFormat: columnFormat, columnLines: extracted.columnBased,
                    chosen: "none",
                    parseResult: parseError
                )
                debugEntries.append(.init(
                    photoIndex: index,
                    rowBasedLines: extracted.rowBased,
                    rowBasedFormat: rowFormat,
                    columnBasedLines: extracted.columnBased,
                    columnBasedFormat: columnFormat,
                    chosenStrategy: "none",
                    parseError: parseError,
                    preprocessedImageData: extracted.preprocessedImageData
                ))
            }
        }

        let allParsed = firstError == nil
        let anyReading = results.contains { $0.rightEye != nil || $0.leftEye != nil }

        if !allParsed || !anyReading {
            let baseMessage = firstError.map(humanReadable) ?? "No SPH/CYL/AX readings could be extracted from the photos. Retake them with better focus and lighting."
            print("=== OCR nav: OCR/parse failure — presenting error alert (allParsed=\(allParsed), anyReading=\(anyReading)) ===")
            let snapshot = OCRDebugSnapshot(entries: debugEntries, overallError: baseMessage)
            await persistFailure(snapshot: snapshot)
            presentError(baseMessage, snapshot: snapshot)
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
        print("=== OCR nav: consistency result = \(outcome.result), message = \(outcome.message ?? "nil") ===")

        switch outcome.result {
        case .ok:
            print("=== OCR nav: OK — navigating to PrescriptionAnalysisView ===")
            phase = .advancing
            presentAnalysis = true
        case .warningOverridable:
            print("=== OCR nav: warningOverridable — presenting override alert ===")
            overridableAlert = AlertContent(message: outcome.message ?? "Readings are inconsistent. Verify before continuing.")
            phase = .awaitingDecision
        case .hardBlock:
            print("=== OCR nav: hardBlock — presenting block alert ===")
            hardBlockAlert = AlertContent(message: outcome.message ?? "Readings cannot be reconciled. Capture additional printouts.")
            phase = .awaitingDecision
        }
    }

    private func presentError(_ message: String, snapshot: OCRDebugSnapshot?) {
        debugSnapshot = snapshot
        errorAlert = ErrorAlertContent(message: message, snapshot: snapshot)
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

    private func logDebug(
        photoIndex: Int,
        rowFormat: String, rowLines: [String],
        columnFormat: String, columnLines: [String],
        chosen: String,
        parseResult: String
    ) {
        print("=== OCR Debug: Photo \(photoIndex + 1) ===")
        print("Row-based: format=\(rowFormat), \(rowLines.count) lines")
        for (i, line) in rowLines.enumerated() {
            print("  R\(i): \(line)")
        }
        print("Column-based: format=\(columnFormat), \(columnLines.count) lines")
        for (i, line) in columnLines.enumerated() {
            print("  C\(i): \(line)")
        }
        print("Chosen strategy: \(chosen)")
        print("Parse result: \(parseResult)")
        print("===")
    }

    private func readingCount(_ result: PrintoutResult?) -> Int {
        guard let r = result else { return 0 }
        return (r.rightEye?.readings.count ?? 0) + (r.leftEye?.readings.count ?? 0)
    }

    private func formatName(_ detection: PrintoutFormatDetectionResult) -> String {
        switch detection {
        case .desktop: return "desktop"
        case .handheld: return "handheld"
        case .unknown: return "unknown"
        }
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
