#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only tool to collect real GRK-6000 fixture captures. Flow: pick a
/// subdir → enter the 24 printed readings once → take a photo → a share
/// sheet immediately pops up with `case-<ts>.jpg` + matching `.json`; pick
/// AirDrop → your Mac. Drop the pair into
/// `HICORTests/OCR/Fixtures/Images/grk6000/<subdir>/`.
///
/// Files are also staged under `Documents/fixtures/<subdir>/` as a backup
/// so you can re-export in one batch later via "Export all".
struct FixtureCaptureView: View {

    enum Subdir: String, CaseIterable, Identifiable {
        case dim_good_framing
        case dim_tilted
        case bright_good_framing
        case dim_poor_framing
        var id: String { rawValue }
        var shouldFail: Bool { self == .dim_poor_framing }
        var display: String { rawValue.replacingOccurrences(of: "_", with: " ") }
    }

    struct Session {
        var subdir: Subdir
        var readings: ReadingsForm
    }

    @State private var draftSubdir: Subdir = .dim_good_framing
    @State private var draftReadings = ReadingsForm()
    @State private var session: Session?
    @State private var showingCamera = false
    @State private var pendingShareURLs: [URL] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var lastSavedStem: String?
    @State private var counts: [Subdir: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                if let session {
                    sessionActiveSection(session)
                } else {
                    setupSection
                }
                corpusStatusSection
            }
            .navigationTitle("Fixture Capture")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: refreshCounts)
            .fullScreenCover(isPresented: $showingCamera) {
                CaptureView(
                    onImagePicked: { image in
                        showingCamera = false
                        savePhoto(image)
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(items: pendingShareURLs)
            }
        }
    }

    // MARK: - Setup (no active session)

    private var setupSection: some View {
        Group {
            Section("Subdirectory") {
                Picker("Subdir", selection: $draftSubdir) {
                    ForEach(Subdir.allCases) { dir in
                        Text(dir.display).tag(dir)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if !draftSubdir.shouldFail {
                readingsEditor(form: $draftReadings)
            } else {
                Section {
                    Text("dim_poor_framing fixtures are expected to fail extraction. JSON will be written with shouldFail: true — no readings needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    startSession()
                } label: {
                    Text("Start session → open camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    exportAll()
                } label: {
                    Label("Export all previous captures", systemImage: "square.and.arrow.up.on.square")
                        .frame(maxWidth: .infinity)
                }
                .disabled((counts.values.reduce(0, +)) == 0)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func startSession() {
        errorMessage = nil
        if !draftSubdir.shouldFail {
            guard draftReadings.isComplete else {
                errorMessage = "Fill in all 24 reading values (or switch to dim_poor_framing)."
                return
            }
        }
        session = Session(subdir: draftSubdir, readings: draftReadings)
        showingCamera = true
    }

    // MARK: - Session active

    @ViewBuilder
    private func sessionActiveSection(_ current: Session) -> some View {
        Section("Current session") {
            LabeledContent("Subdir") { Text(current.subdir.display) }
            if current.subdir.shouldFail {
                Text("shouldFail: true (no readings)").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("24 readings locked in").font(.footnote).foregroundStyle(.secondary)
            }
            if let lastSavedStem {
                Text("Saved: \(lastSavedStem)").font(.footnote).foregroundStyle(.green)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }

        Section {
            Button {
                showingCamera = true
            } label: {
                Label("Take another photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if !pendingShareURLs.isEmpty {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Re-open share sheet for last capture", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }

            Button(role: .destructive) {
                session = nil
                draftReadings = ReadingsForm()
                lastSavedStem = nil
                errorMessage = nil
            } label: {
                Text("End session (change subdir or values)").frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Reading editor

    @ViewBuilder
    private func readingsEditor(form: Binding<ReadingsForm>) -> some View {
        Section("Right eye (R)") {
            rowFields(label: "R1", binding: form.right.r1)
            rowFields(label: "R2", binding: form.right.r2)
            rowFields(label: "R3", binding: form.right.r3)
            rowFields(label: "AVG", binding: form.right.avg)
        }
        Section("Left eye (L)") {
            rowFields(label: "L1", binding: form.left.r1)
            rowFields(label: "L2", binding: form.left.r2)
            rowFields(label: "L3", binding: form.left.r3)
            rowFields(label: "AVG", binding: form.left.avg)
        }
    }

    private func rowFields(label: String, binding: Binding<ReadingsForm.Row>) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 40, alignment: .leading).font(.subheadline.monospaced())
            TextField("sph", text: binding.sph)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            TextField("cyl", text: binding.cyl)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
            TextField("ax", text: binding.ax)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .autocorrectionDisabled()
        }
    }

    // MARK: - Corpus status

    private var corpusStatusSection: some View {
        Section("Corpus staged on device") {
            ForEach(Subdir.allCases) { dir in
                HStack {
                    Text(dir.display)
                    Spacer()
                    Text("\(counts[dir] ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text("Each capture pops a share sheet — AirDrop to your Mac, then drop the pair into HICORTests/OCR/Fixtures/Images/grk6000/<subdir>/.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: - Save + share

    private func savePhoto(_ image: UIImage) {
        guard let session else { return }
        errorMessage = nil
        do {
            let stem = "\(session.subdir.rawValue)-case-\(Int(Date().timeIntervalSince1970))"
            let dir = try fixturesDir(for: session.subdir)
            let jpgURL = dir.appendingPathComponent("\(stem).jpg")
            let jsonURL = dir.appendingPathComponent("\(stem).json")
            guard let jpgData = image.jpegData(compressionQuality: 0.9) else {
                throw NSError(domain: "FixtureCaptureView", code: 1, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"])
            }
            try jpgData.write(to: jpgURL, options: .atomic)
            let jsonData = try JSONSerialization.data(
                withJSONObject: session.readings.jsonBody(shouldFail: session.subdir.shouldFail),
                options: [.prettyPrinted, .sortedKeys]
            )
            try jsonData.write(to: jsonURL, options: .atomic)
            lastSavedStem = stem
            pendingShareURLs = [jpgURL, jsonURL]
            refreshCounts()
            // Present share sheet on the next runloop tick so the camera's
            // fullScreenCover has fully dismissed first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingShareSheet = true
            }
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func exportAll() {
        errorMessage = nil
        do {
            let root = try rootDir()
            let urls = try collectFixtureURLs(under: root)
            guard !urls.isEmpty else {
                errorMessage = "No captures staged yet."
                return
            }
            pendingShareURLs = urls
            showingShareSheet = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func collectFixtureURLs(under root: URL) throws -> [URL] {
        var out: [URL] = []
        for dir in Subdir.allCases {
            let subdirURL = root.appendingPathComponent(dir.rawValue, isDirectory: true)
            let contents = (try? FileManager.default.contentsOfDirectory(at: subdirURL, includingPropertiesForKeys: nil)) ?? []
            for url in contents where ["jpg", "json"].contains(url.pathExtension.lowercased()) {
                out.append(url)
            }
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func rootDir() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let root = docs.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixturesDir(for subdir: Subdir) throws -> URL {
        let dir = try rootDir().appendingPathComponent(subdir.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func refreshCounts() {
        var next: [Subdir: Int] = [:]
        for dir in Subdir.allCases {
            let url = (try? fixturesDir(for: dir)) ?? URL(fileURLWithPath: "/dev/null")
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            next[dir] = contents.filter { $0.pathExtension.lowercased() == "jpg" }.count
        }
        counts = next
    }
}

struct ReadingsForm {
    struct Row {
        var sph: String = ""
        var cyl: String = ""
        var ax: String = ""
        var isComplete: Bool {
            !sph.trimmingCharacters(in: .whitespaces).isEmpty
                && !cyl.trimmingCharacters(in: .whitespaces).isEmpty
                && !ax.trimmingCharacters(in: .whitespaces).isEmpty
        }
        func dict() -> [String: String] {
            ["sph": sph.trimmingCharacters(in: .whitespaces),
             "cyl": cyl.trimmingCharacters(in: .whitespaces),
             "ax": ax.trimmingCharacters(in: .whitespaces)]
        }
    }
    struct Section {
        var r1 = Row()
        var r2 = Row()
        var r3 = Row()
        var avg = Row()
        var isComplete: Bool { r1.isComplete && r2.isComplete && r3.isComplete && avg.isComplete }
        func dict() -> [String: [String: String]] {
            ["r1": r1.dict(), "r2": r2.dict(), "r3": r3.dict(), "avg": avg.dict()]
        }
    }
    var right = Section()
    var left = Section()
    var isComplete: Bool { right.isComplete && left.isComplete }

    func jsonBody(shouldFail: Bool) -> [String: Any] {
        if shouldFail {
            return ["shouldFail": true]
        }
        return [
            "shouldFail": false,
            "expected": [
                "right": right.dict(),
                "left": left.dict()
            ]
        ]
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
