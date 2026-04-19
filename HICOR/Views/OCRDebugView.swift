#if DEBUG
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photo \(entry.photoIndex + 1)")
                    .font(.headline)
                Spacer()
                Text("Chosen: \(entry.chosenStrategy)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint.opacity(0.15), in: Capsule())
            }

            if let data = entry.preprocessedImageData, let uiImage = UIImage(data: data) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preprocessed image (what Vision saw)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if let parseError = entry.parseError {
                Text(parseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            strategyBlock(
                title: "Row-based",
                format: entry.rowBasedFormat,
                lines: entry.rowBasedLines
            )
            strategyBlock(
                title: "Column-based",
                format: entry.columnBasedFormat,
                lines: entry.columnBasedLines
            )
        }
        .padding()
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func strategyBlock(title: String, format: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Text("(\(format))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if lines.isEmpty {
                Text("(empty)")
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text("\(i): \(line)")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
#endif
