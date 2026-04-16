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
| `Services/OCR/VisionTextExtractor.swift` | `TextExtracting` protocol + `VNRecognizeTextRequest` impl. **`usesLanguageCorrection = false`** — required for numeric accuracy; language correction mangles autorefractor digits |
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
- No third-party dependencies. Apple SDKs only.
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

## Build & Test

```bash
xcodegen generate
xcodebuild -project HICOR.xcodeproj -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test CODE_SIGNING_ALLOWED=NO
```
