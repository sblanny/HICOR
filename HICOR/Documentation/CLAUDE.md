# HICOR — Claude Development Guide

## Project

**HICOR** (Highlands Church Optical Refraction) — iOS app that photographs autorefractor printouts, OCRs them on-device, applies evidence-based prescription averaging, matches to a fixed lens inventory, and saves shared records to CloudKit. Used by mission-trip volunteers in remote/offline conditions.

**Bundle ID:** `com.creativearchives.hicor`
**CloudKit container:** `iCloud.com.creativearchives.hicor` (public database)
**Min iOS:** 17.0
**Target launch:** May 1, 2026 mission trip

## Folder Structure

```
HICOR/
├── project.yml                      # xcodegen project definition (source of truth)
├── HICOR/
│   ├── App/                         # @main entry, root view
│   ├── Models/                      # data structures (Codable + @Model)
│   ├── Services/                    # persistence, CloudKit, lens inventory
│   │   └── OCR/                     # Vision text extraction + printout parsers
│   ├── Utilities/                   # constants, shared enums
│   ├── Views/                       # SwiftUI screens
│   ├── Resources/                   # JSON, asset catalogs
│   └── Documentation/               # markdown docs
├── HICORTests/                      # XCTest unit tests
│   └── OCR/                         # parser, normalizer, validator tests + Fixtures/
└── Scripts/                         # one-shot tooling (e.g. inventory generator)
```

### File Responsibilities

| File | Responsibility |
|---|---|
| `App/HICORApp.swift` | `@main` entry and DI root: owns the single `ModelContainer` + all services (`PersistenceService`, `CloudKitService`, `SyncCoordinator`, `BackgroundSyncService`), wires them into the scene, bootstraps lens inventory, and fires `BackgroundSyncService.syncIfNeeded` on foreground |
| `App/ContentView.swift` | `NavigationStack` root rooted at `SessionSetupView`; resets via `.hicorReturnToRoot` notification |
| `Models/RawReading.swift` | One reading line from a printout (SPH/CYL/AX, eye, source photo index) |
| `Models/EyeReading.swift` | All readings for one eye from one photo + machine AVG line |
| `Models/PatientRefraction.swift` | SwiftData `@Model` — the persisted patient record |
| `Models/SessionSettings.swift` | `UserDefaults`-backed last session date and location |
| `Models/SessionContext.swift` | `@Observable` holder for date + location passed through NavigationStack |
| `Models/PhotoCaptureState.swift` | `@Observable` capture-screen state: photos list, PD entry, analyze/commit gating |
| `Models/LensInventory.swift` | `LensOption` and `LensInventory` Codable structs |
| `Services/PersistenceService.swift` | `@ModelActor` — actor-isolated `ModelContext` providing `insert` / `fetch` / `fetchUnsynced` / `markSynced` / `save`. Constructed once in `HICORApp.init` and injected |
| `Services/LensInventoryService.swift` | Loads `DefaultInventory.json`, supports user override in Documents |
| `Services/CloudKitService.swift` | `CKRecord` conversion + real `CKDatabase` save/fetch (DI via `CKDatabaseProtocol`). `saveRecord` returns the new record ID; persistence-side mutation happens in `PersistenceService.markSynced` |
| `Services/SyncCoordinator.swift` | `@MainActor @Observable` orchestrator injected with persistence + cloudKit: local `insert` → CloudKit save → `markSynced` |
| `Services/BackgroundSyncService.swift` | `@MainActor @Observable` retry loop injected with persistence + cloudKit; resyncs unsynced records on foreground |
| `Views/SessionSetupView.swift` | Launch screen: date + location, pre-filled from `SessionSettings.load()` |
| `Views/PatientEntryView.swift` | Numeric patient number entry with auto-focus |
| `Views/PhotoCaptureView.swift` | 2–5 photo capture, thumbnail row, PD banner, DEBUG simulate-no-PD toggle |
| `Views/CameraPickerView.swift` | `UIImagePickerController` wrapper; falls back to `.photoLibrary` on simulator |
| `Views/FullScreenPhotoView.swift` | Pinch + double-tap zoom viewer for thumbnails |
| `Views/AnalysisPlaceholderView.swift` | Spinner screen; runs OCR pipeline + ConsistencyValidator; presents hard-block/overridable/error alerts; on success builds in-memory `PatientRefraction` and navigates to `PrescriptionAnalysisView`. Does NOT save — persistence happens on Save & Return |
| `Views/PrescriptionAnalysisView.swift` | Read-only review of parsed readings per photo (per-eye SPH/CYL/AX, machine AVG/`*` line + confidence, low-confidence styling, PD). Save & Return calls `sync.save(refraction)` then posts `.hicorReturnToRoot` |
| `Services/OCR/VisionTextExtractor.swift` | **Fallback only.** Holds the `TextExtracting` protocol, `ExtractedText`/`TextBox` structs, and the reconstruction helpers (`computeAdaptiveThresholds`, `reconstructRows`, `reconstructColumnarLines`) that `MLKitTextExtractor` reuses. The Vision implementation of `TextExtracting` remains so the default extractor can be reverted by one line. Do not add Vision-only tuning here. |
| `Services/OCR/MLKitTextExtractor.swift` | Default `TextExtracting` implementation. Wraps `MLKitTextRecognition.TextRecognizer`, converts ML Kit `Text.blocks.lines` to `[TextBox]` (pixel → Vision-normalized coordinates with Y flip), then calls `VisionTextExtractor`'s static reconstruction helpers. `PreprocessingVariant` + `revision` params are accepted for protocol stability but ignored — ML Kit handles preprocessing internally. Per-line confidence is hardcoded `1.0` (Swift API does not expose it). |
| `Services/OCR/PrintoutResult.swift` | Codable carrier struct: per-eye `EyeReading`, optional PD, machine type, source photo index, raw text, optional handheld `*` confidence per eye |
| `Services/OCR/PrintoutParser.swift` | Detects desktop vs handheld (`-REF-` → handheld; `AVG`/`GRK`/`Highlands` → desktop; `*`+brackets fallback → handheld) and routes |
| `Services/OCR/DesktopFormatParser.swift` | Parses `[R]`/`<R>` and `[L]`/`<L>` sections, AVG line per eye, and `PD: NN mm` |
| `Services/OCR/HandheldFormatParser.swift` | Parses `-REF-` → bracketed eye sections; `E`-suffixed readings flagged `lowConfidence`; `*` line captures machine avg + 1-9 confidence per eye |
| `Services/OCR/ReadingNormalizer.swift` | SPH/CYL quarter-diopter rounding, AX clamp 1-180, OCR string fixes (O→0, l→1, S→5, whitespace) |
| `Services/OCR/OCRService.swift` | `@Observable` coordinator. Init takes any `TextExtracting` so tests inject stubs. Throws `OCRError.{noTextFound, unrecognizedFormat, insufficientReadings}` |
| `Services/OCR/ConsistencyValidator.swift` | Stateless value type. Sign-mismatch (avg R vs L SPH): photoCount<3 → `.hardBlock`, ≥3 → `.warningOverridable`. Per-eye SPH/CYL spread > 0.75 D → `.warningOverridable` |
| `Utilities/Constants.swift` | App-wide constants and shared enums (`Eye`, `MachineType`, `ConsistencyResult`) |
| `Resources/DefaultInventory.json` | 245 lenses (49 SPH × 5 CYL), generated by `Scripts/generate_default_inventory.swift` |

## Phase Plan

| Phase | Scope | Status |
|---|---|---|
| 1 | Project skeleton, models, lens inventory, persistence, CloudKit stub | **Complete** |
| 2 | Real CloudKit integration, `SyncCoordinator`, iCloud entitlements | **Complete** |
| 3 | Camera capture, photo storage, background sync, navigation shell (pulled Phase 8 session/patient-entry and Phase 7 result-placeholder forward for end-to-end walkthrough) | **Complete** |
| 4 | Vision OCR extraction (desktop + handheld parsers) | Pending |
| 5 | Prescription averaging algorithm (after RESEARCH.md deep pass) | Pending |
| 6 | Lens matching algorithm (real `closestLens`) | Pending |
| 7 | Real result screen (replaces `ResultPlaceholderView`), history/lookup screen | Pending |
| 8 | Polish session/patient-entry UI to final spec (already scaffolded in Phase 3) | Pending |
| 9 | Polish, accessibility, TestFlight release | Pending |

## Coding Conventions

- Swift 5.10+, SwiftUI, async/await for async work.
- Third-party dependencies: **Google ML Kit Text Recognition** only, via CocoaPods. All other code is Apple SDKs. See **Text Extraction (Google ML Kit)** below for why and how.
- One type per file, named after the type.
- Models are `struct` unless they need SwiftData persistence (`@Model class`).
- Services are `final class` (reference semantics) with a `static let shared` plus an `init` overload that accepts dependencies for tests.
- `@Attribute(.externalStorage)` for any large `Data`/`[Data]` field on a `@Model`.
- Tests use in-memory `ModelContainer` and `UserDefaults(suiteName:)` sandboxes — never the standard suite.
- Build must compile with **zero warnings** before commit.

## CloudKit

- **Container:** `iCloud.com.creativearchives.hicor` (public DB) — provisioned in Apple Developer portal.
- **Entitlements:** `HICOR/HICOR.entitlements` declares `com.apple.developer.icloud-services` (`CloudKit`) and `com.apple.developer.icloud-container-identifiers`. Wired via `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
- **Real network calls:** `CloudKitService.saveRecord` / `fetchRecords` hit the public DB. `CKDatabase` is hidden behind `CKDatabaseProtocol` so unit tests inject a `MockCKDatabase`. Database resolution is lazy so `CloudKitService.shared` can construct safely on app launch in unsigned/test builds (the real `CKContainer` is only touched on first save/fetch).
- **End-to-end verification:** requires a signed device build with an iCloud-signed-in account. Simulator unit tests cover behavior via mock; they do not exercise the real CloudKit network.
- **Sync flow:** `SyncCoordinator.save(_:)` always inserts locally first, then attempts the CloudKit save and explicitly calls `persistence.save()` on success so the mutated `syncedToCloud` / `cloudKitRecordID` fields hit disk before the app can be backgrounded. CloudKit failures leave the record `syncedToCloud = false` for Phase 3 background retry.
- **Why public DB:** records are shared across all team devices.
- **Why manual sync (not `NSPersistentCloudKitContainer`):** Apple's automatic sync targets the private DB only.
- **CloudKit payload is metadata-only.** `CKRecord` holds patient number, dates, session info, parsed SPH/CYL/AX, PD, matched lenses, and a JSON blob of raw readings — no photo bytes. Photos stay local via SwiftData's `@Attribute(.externalStorage)`. Rationale: CKRecord fields cap at ~1 MB; inlining 2–5 JPEGs regularly exceeded that and triggered `Limit Exceeded / record too large`. Phase 9 may add `CKAsset`-based photo sync if needed.

## Inventory Architecture

Inventory is **data-driven JSON**, not hardcoded enums. The bundled `DefaultInventory.json` is the seed; the runtime can write a modified copy to the app's Documents directory and that copy takes precedence on next launch. This lets a future build mark individual lenses unavailable or extend the cylinder set without a code change.

## Research Items

| # | Question | Light pass status |
|---|---|---|
| 1 | Vector averaging method for SPH/CYL/AX | Deep Pass Complete (Thibos M/J0/J45 equal-weight) |
| 2 | Outlier rejection threshold | Deep Pass Complete (k=3 MAD in power-vector space + 1.00 D ANSI floor) |
| 3 | Use of machine AVG (`*`) line | Deep Pass Complete (peer reading; handheld `*` gated on confidence ≥ 5) |
| 4 | Lens-match rounding method | Deep Pass Complete (SE-preserving snap with cyl-distance tiebreak) |

See `RESEARCH.md` for sources, light-pass conclusions, and the **✅ Final Decision** sections that lock in the algorithms for Phase 5.

## Constraints

- **Offline-first.** OCR, averaging, persistence all work without internet.
- **iOS 17+.** SwiftData and the modern NavigationStack are required.
- **iPhone first.** iPad layout is a future version.
- **No login.** Device identity (`identifierForVendor`) only.

## Known Limitations

- **v1 scope: exactly one photo per patient.** `Constants.minPhotosRequired` and `Constants.maxPhotosAllowed` are both `1` while we stabilize single-photo OCR end-to-end with ML Kit. This removes multi-photo aggregation, cross-photo averaging, and the photo-count-driven hardBlock branch of `ConsistencyValidator` as debugging variables. The `.hardBlock` enum case and alert branch are kept in place (unreachable today) so that restoring multi-photo capture is a surgical change: raise `maxPhotosAllowed`, reintroduce the `photoCount` parameter to `ConsistencyValidator.validate`, and restore the "Please capture additional printouts" hard-block message. Phase 5 averaging and `Docs/RESEARCH.md` M/J0/J45 work continue to assume multi-photo eventually comes back — do not delete averaging code on the single-photo branch.
- **OCR may extract fewer readings than printed** (e.g. 5 of 8) when the recognizer fragments a reading line onto multiple observations and only the SPH column survives reconstruction. Less frequent on ML Kit than it was on Vision, but still possible. Averaging with 5 good readings still produces a clinically valid prescription.
- **SPH-only readings are valid clinical data.** Some autorefractor measurements print SPH with no CYL/AX (the machine detected no astigmatism on that sample). Both parsers accept these and store `RawReading` with `isSphOnly = true` and placeholder `cyl = 0.0`, `ax = 0`. `ConsistencyValidator` already filters them out of the cyl spread check. **Phase 5 averaging must also filter on `isSphOnly`**: include the SPH value in the SPH average, but exclude the placeholder cyl/ax from any J0/J45 vector decomposition or CYL/AX averaging. Treat them as "SPH-contributing only" peers.

## Persistence Architecture

### App-rooted DI

`HICORApp.init()` is the single source of persistence construction. It builds the `ModelContainer` once, then constructs `PersistenceService`, `CloudKitService`, `SyncCoordinator`, and `BackgroundSyncService` with explicit dependencies. The scene receives `.modelContainer(container)` (so SwiftUI `@Query` / `@Environment(\.modelContext)` work) and `.environment(syncCoordinator)` (so `AnalysisPlaceholderView` can pull it out). No service declares a `static let shared` — tests and production both go through the same initializers.

### `@ModelActor` isolation

`PersistenceService` is a `@ModelActor actor`. Its `ModelContext` is created on the actor's executor and never touched from the main queue, which eliminates the *"SwiftData.ModelContext: Unbinding from the main queue"* warnings previous code triggered. All CRUD methods are `async throws`; callers (`SyncCoordinator`, `BackgroundSyncService`, tests) `await` them.

`CloudKitService.saveRecord` returns the CloudKit `recordName` instead of mutating the passed-in model. The caller passes that ID back into `PersistenceService.markSynced(id:cloudKitRecordID:)` so the mutation happens inside the actor. This keeps all writes to `@Model` instances on the actor's isolation domain.

### SwiftData + CloudKit opt-out

`HICOR.entitlements` declares CloudKit services, which by default would make `ModelConfiguration` set `cloudKitDatabase` to `.automatic` and force SwiftData's built-in CloudKit sync on `ModelContainer` init. That path requires the private DB plus all stored properties optional or with inline defaults — we use the public DB and `PatientRefraction` has many non-optional stored properties, so leaving it automatic crashes device installs with `SwiftDataError.loadIssueModelContainer`.

`HICORApp.makeModelContainer()` therefore sets `cloudKitDatabase: .none`, disabling SwiftData's automatic integration entirely. Our CloudKit sync is manual via `SyncCoordinator` / `CloudKitService`. The container init also has a one-shot retry that deletes `config.url` if the initial load fails, as defense-in-depth for genuine schema-mismatch corruption during future migrations.

### Known future work: Swift 6 strict concurrency

In Swift 5.10 mode the actor methods freely accept and return `PatientRefraction` instances across the actor boundary; `@Model` classes aren't `Sendable`, so a future move to Swift 6 strict-concurrency mode will produce compile errors at those boundaries. The canonical migration is to pass `PersistentIdentifier` or `Sendable` struct snapshots across the actor instead. Deferred, not a runtime issue today.

### OCR real-device validation

After any OCR pipeline change, validate against real handheld printouts before shipping. **Target:** ≥70% reading extraction rate (readings recovered / readings visible on the printout) across ≥5 real-device captures under mixed conditions (clean, slightly tilted, faded thermal). Use `OCRDebugSnapshot.Entry.variantScores` to diagnose which variant/revision won and why. Synthetic fixture tests are necessary but not sufficient — they cannot catch Vision-level degradations.

**ParseScorer weights are provisional.** The weights (0.50 / 0.25 / 0.15 / 0.10) in `OCRService.swift` shipped on 2026-04-16 **uncalibrated**: the only real-capture debug logs available at that time were from a single patient's printout, and calibrating against one capture would overfit. The scorer emits verbose per-call logging (variant / reconstruction / revision / readings / component scores / total) so field captures from mixed patients can be replayed offline for calibration. Revisit weights once ≥5 captures from **distinct** printouts are available (the May 1 mission trip is the expected source).

## Text Extraction (Google ML Kit)

### Why ML Kit, not Apple Vision

Real-device testing of Apple Vision (`VNRecognizeTextRequest`) on the handheld autorefractor printout showed repeated fragmentation of decimal numbers — e.g. `+1.25` recognized as two separate observations (`+1` and `25`) with no coordinate relationship the reconstruction code could stitch. Multi-pass scoring across preprocessing variants and revisions did not close the gap. See `OCR_ASSESSMENT.md` and `CODEX_OCR_REVIEW.md` for the diagnosis that led to the swap.

Google ML Kit Text Recognition v2 produces a `Block → Line → Element` hierarchy with atomic decimal tokens and cleaner row segmentation on device. The protocol boundary (`TextExtracting`) is unchanged — only the implementation is swapped. `VisionTextExtractor` is retained as a one-line-revert fallback.

### Integration: CocoaPods + xcodegen hybrid

**Build entry point:** `HICOR.xcworkspace` (not `HICOR.xcodeproj`). CocoaPods' Pods project lives in the workspace; building the bare `.xcodeproj` will fail to link ML Kit.

Fresh clone setup:

```bash
xcodegen generate        # produces HICOR.xcodeproj from project.yml
pod install              # produces HICOR.xcworkspace and Pods/
open HICOR.xcworkspace   # always open the workspace, never the project
```

**Rules of thumb:**
- After any `project.yml` change → `xcodegen generate && pod install`. xcodegen rewrites the `.xcodeproj`; `pod install` re-integrates the Pods target into the workspace.
- `Podfile` pins `GoogleMLKit/TextRecognition` unqualified (latest). Version bump: edit `Podfile`, run `pod update GoogleMLKit/TextRecognition`, commit `Podfile.lock`.
- `HICOR.xcworkspace/` is tracked (CocoaPods owns it). `Pods/` is gitignored; re-fetched via `pod install`.
- The `Podfile` `post_install` hook sets `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` — ML Kit's static .framework ships an arm64 iOS-device slice but no arm64 simulator slice, so Apple Silicon simulator builds must run x86_64 via Rosetta. The hook also lifts pod deployment targets to iOS 17 to silence Xcode 26 warnings about pre-iOS-12 minimums in transitive pods.
- `project.yml` sets `ENABLE_USER_SCRIPT_SANDBOXING: NO` at the workspace level because the `[CP] Embed Pods Frameworks` run-script writes to paths outside its declared outputs; sandboxing it fails the build with `rsync … Operation not permitted`.

**Required local tool:** `cocoapods` (`brew install cocoapods`). There is no SPM path — Google does not publish ML Kit as a Swift package, and manual xcframework vendoring failed because six of the transitive pods ship source-only.

### Coordinate system

ML Kit returns each line's `frame` in **image pixel coordinates, top-left origin**. `TextBox` (and everything downstream — row clustering, section detection, column reconstruction) expects **Vision-normalized 0–1 coordinates, bottom-left origin**. `MLKitTextExtractor.toTextBoxes(_:imageSize:)` performs the Y-flip and normalization. If the flip is ever removed, row sorting reverses and every section marker lands on the wrong side. Covered by the existing reconstruction tests in `VisionTextExtractorTests`.

### Confidence

`MLKTextLine` in ML Kit v2's Swift API does not expose a per-line confidence. `MLKitTextExtractor` hardcodes `confidence = 1.0`, which means the 10% confidence weight in `ParseScorer` (`OCRService.swift`) currently goes uniform across reconstructions. Acceptable for single-pass scoring (the confidence weight is the tiebreaker, not the signal). If multi-pass returns, derive a heuristic confidence from line content (digit density, length, marker presence) rather than trusting ML Kit 1.0 values.

### Rollback

If a future ML Kit regression makes results worse than Vision, change `OCRService.swift:126` from `MLKitTextExtractor()` back to `VisionTextExtractor()`. The Vision path is kept compiled and tested exactly so this revert is a one-line change.

## Build & Test

```bash
xcodegen generate
pod install
xcodebuild -workspace HICOR.xcworkspace -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test CODE_SIGNING_ALLOWED=NO
```

For real-device test runs use `-destination 'id=<device-UDID>' -allowProvisioningUpdates`. The iOS 26 Apple Silicon simulator cannot currently launch HICOR because ML Kit lacks an arm64 simulator slice — use an Intel-archive simulator image, Rosetta, or a physical device.
