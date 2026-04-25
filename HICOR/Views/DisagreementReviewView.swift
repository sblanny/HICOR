import SwiftUI

/// Shown when ConsistencyValidator flags a disagreement across captured
/// printouts. Replaces the blind "Readings don't agree" popup with a
/// read-only screen that shows every parsed reading per printout so the
/// operator can verify what OCR extracted before deciding to recapture.
/// Per the no-manual-correction rule, the operator cannot edit values —
/// the only actions are "capture another" or "start over."
struct DisagreementReviewView: View {
    enum Mode {
        /// currentCount = printouts already captured (<= maxPrintoutsAllowed - 1).
        case addAnother(reason: String, currentCount: Int)
        /// Reached the max; operator must consult team leader and restart.
        case escalate(reason: String)
    }

    let mode: Mode
    let results: [PrintoutResult]
    let onAddAnother: () -> Void
    let onStartOver: () -> Void

    @State private var confirmStartOver = false
    @State private var showAbout = false

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader(
                onShowAbout: { showAbout = true }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    banner
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What the scanner read")
                            .font(.headline)
                        Text("Verify the readings below. If a value looks wrong, capture another printout — we'll keep all of them and pick the best match.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(results.enumerated()), id: \.offset) { idx, result in
                            PrintoutReadingsCard(index: idx, result: result)
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) { actionBar }
        .alert("CLEAR Ministry", isPresented: $showAbout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Highlands Church Optical Refraction\nVersion 1.0")
        }
        .alert("Start over?", isPresented: $confirmStartOver) {
            Button("Cancel", role: .cancel) {}
            Button("Start Over", role: .destructive) { onStartOver() }
        } message: {
            Text("This will discard all captured printouts for this patient.")
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(bannerTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(bannerReason)
                .font(.subheadline)
            Text(bannerGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private var bannerTitle: String {
        switch mode {
        case .addAnother: return "Readings don't agree"
        case .escalate:   return "Consult team leader"
        }
    }

    private var bannerReason: String {
        switch mode {
        case .addAnother(let reason, _): return reason
        case .escalate(let reason):      return reason
        }
    }

    private var bannerGuidance: String {
        switch mode {
        case .addAnother(_, let currentCount):
            return "You have \(currentCount) of up to \(Constants.maxPrintoutsAllowed) printouts. Capture another so we can cross-check."
        case .escalate:
            return "\(Constants.maxPrintoutsAllowed) printouts captured and readings still don't agree. Please consult your team leader before proceeding."
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            switch mode {
            case .addAnother:
                Button(action: onAddAnother) {
                    Text("Capture another printout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    confirmStartOver = true
                } label: {
                    Text("Start over")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            case .escalate:
                Button(role: .destructive) {
                    confirmStartOver = true
                } label: {
                    Text("Start over")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .background(.background)
    }
}
