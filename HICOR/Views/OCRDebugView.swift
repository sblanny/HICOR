import SwiftUI

struct OCRDebugView: View {
    let snapshot: OCRDebugSnapshot
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(snapshot.overallError)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.bottom, 4)

                    ForEach(Array(snapshot.entries.enumerated()), id: \.offset) { _, entry in
                        photoCard(entry)
                    }
                }
                .padding()
            }
            .navigationTitle("OCR Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }

    private func photoCard(_ entry: OCRDebugSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photo \(entry.photoIndex + 1)")
                    .font(.headline)
                Spacer()
                Text(entry.detectedFormat.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
            }

            if let parseError = entry.parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if entry.extractedLines.isEmpty {
                Text("(no text extracted)")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(entry.extractedLines.enumerated()), id: \.offset) { i, line in
                        Text("\(i + 1): \(line)")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}
