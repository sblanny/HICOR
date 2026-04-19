# ROI Pipeline for GRK-6000 OCR under Dim Lighting

## Purpose

Reach Scanner-Pro-grade OCR accuracy on the GRK-6000 desktop autorefractor thermal printout captured in a dim refraction room. Current failure mode: `MLKitTextExtractor` runs ML Kit on the whole photo, and on low-contrast captures ML Kit mangles individual SPH/CYL cells (dropped leading characters, merged columns, glyph substitution) even though row grouping and tilt correction work. We cannot fix this in post-processing — the raw cell reads are corrupt. We fix it by (a) improving the input image (rectification + enhancement) and (b) running ML Kit on each cell in isolation so it has less content to confuse itself with.

## Scope

**In scope for this work (May 1, 2026 trip):**
- GRK-6000 desktop autorefractor printout only.
- New capture UX with torch and framing guide.
- Post-capture rectification + enhancement + per-cell ROI OCR pipeline.
- `MLKitTextExtractor` retained as explicit fallback.
- All-or-nothing extraction: any missing required cell is a re-capture error.

**Out of scope:**
- Handheld autorefractor format (revisit for July trip).
- Auto-capture / live rectangle detection (escalation path if manual shutter proves insufficient).
- Manual-correction UI for OCR results (explicitly rejected per user stance).
- Per-eye "measurement refused" markers for single-eye-only patients (post-May revisit).

## Constraints and ground rules

- **No manual correction UI.** If the user has to edit OCR results, the app's value proposition collapses (user could just read the slip themselves). Invest effort in recognition, not in downstream editing.
- **All-or-nothing extraction.** For V1, missing any required cell is an error. The error surfaces as a "re-capture" prompt, never a partial prescription.
- **On-device only.** Swift + ML Kit Text Recognition v2 (already vendored). No network calls, no cloud OCR.
- **Latency budget ≤3 seconds** from shutter to results screen.
- **`TextExtracting` protocol boundary stays.** Downstream parser/normalizer/validator/scorer are not touched by this work.

## Architecture

```
PhotoCaptureView
   │
   ▼
CaptureView (AVFoundation, torch + framing overlay)
   │
   │  UIImage
   ▼
ROIPipelineExtractor  (conforms to TextExtracting)
   │
   ├─ DocumentRectifier    : detect printout edges, perspective-warp to rectangle
   ├─ ImageEnhancer        : contrast + gamma + unsharp on rectified image
   ├─ AnchorDetector       : ML Kit pass #1, locate <R>/<L>/SPH/CYL/AX/AVG labels
   ├─ CellLayout + anchors → 24 CellROI rectangles
   ├─ CellROIExtractor     : crop each cell with ~10% padding
   └─ CellOCR (×24)        : ML Kit per cell, one retry with stronger enhancement on failure
   │
   │  rowBased: [String] matching the current ExtractedText shape
   ▼
PrintoutParser → ReadingNormalizer → ConsistencyValidator   (unchanged)
```

### Why this shape works

Two layered wins:

1. **Rectification + enhancement fix the input.** The current pipeline feeds ML Kit a raw, tilted, dim, clutter-surrounded photo. The ROI pipeline feeds ML Kit a cropped, square-aligned, high-contrast rectangle with only the printout visible. Most of the accuracy gap closes here.

2. **Per-cell OCR removes ML Kit's cross-cell confusion.** On a dense thermal table, ML Kit sometimes merges adjacent columns (`3.7517` = `3.75` + `17`), drops leading digits, or substitutes glyphs in response to neighboring ink density. Feeding it a single cell with whitespace padding eliminates those failure modes by construction.

Anchor-text coordinate frames (`<R>`, `<L>`, `SPH`, `CYL`, `AX`, `AVG`) give us self-calibration per capture. The anchors are large, bold, and survive low-contrast conditions that kill data cells, so they're a reliable coordinate reference across lighting variation, printer drift, and residual skew after rectification.

## Components

All new files under `HICOR/Services/OCR/ROI/` except the capture view.

### `HICOR/Views/CaptureView.swift` (new)

Replaces `CameraPickerView`. AVFoundation-backed live preview with:
- Torch toggle (bottom-left button). Uses `AVCaptureDevice.setTorchModeOn(level:)`. Disabled when `hasTorch == false`.
- Shutter button (bottom-center, large).
- Cancel button (top-left).
- Dashed-rectangle SwiftUI overlay sized to GRK-6000's ~4:3 landscape aspect ratio, drawn inside the preview.

Contract: takes a completion closure `(UIImage) -> Void`, same as `CameraPickerView`.

### `HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift` (new)

```swift
enum DocumentRectifier {
    /// Detects the printout rectangle in `image` and returns a perspective-
    /// corrected UIImage cropped to just the printout, normalized to
    /// long-side-horizontal orientation. Returns nil when no suitable
    /// rectangle is found.
    static func rectify(_ image: UIImage) -> UIImage?
}
```

Implementation: `VNDetectRectanglesRequest` with `minimumConfidence = 0.7`, `minimumAspectRatio = 0.5`, `maximumAspectRatio = 2.0`. When multiple rectangles match, choose the largest one whose center falls within the inner 70% of the image (biases toward the framing-guide area, against background clutter). Warp with `CIFilter.perspectiveCorrection`.

### `HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift` (new)

```swift
enum ImageEnhancer {
    enum Strength { case standard, aggressive }
    static func enhance(_ image: UIImage, strength: Strength = .standard) -> UIImage
}
```

Pure function. Core Image pipeline:
- `CIColorControls` — contrast +1.3, brightness +0.05 (standard) or +1.6 / +0.1 (aggressive).
- `CIGammaAdjust` — power 0.7 (standard) or 0.5 (aggressive), to lift dim pixels.
- `CIUnsharpMask` — radius 2.0, intensity 0.5, to sharpen glyph edges.

Aggressive variant is used by `CellOCR` on retry.

### `HICOR/Services/OCR/ROI/AnchorDetector.swift` (new)

```swift
struct SectionAnchors {
    let eyeMarker: CGRect   // <R>/[R] or <L>/[L]
    let sph: CGRect
    let cyl: CGRect
    let ax: CGRect
    let avg: CGRect
}

struct Anchors {
    let right: SectionAnchors
    let left: SectionAnchors
}

enum AnchorDetector {
    enum Error: Swift.Error { case insufficientAnchors(missing: [String]) }
    static func detectAnchors(in image: UIImage) async throws -> Anchors
}
```

Runs ML Kit on the full enhanced image, filters results for anchor tokens. Matching is case-insensitive and accepts both `<R>`/`[R]` and `<L>`/`[L]` bracket styles. The GRK-6000 prints SPH/CYL/AX/AVG labels **once per eye section**, so there are up to 10 anchor rectangles (5 per section). The detector groups anchors into sections using the `<R>`/`<L>` eye-marker Y positions — anchors whose vertical center falls within a section's vertical band belong to that section.

Throws `insufficientAnchors` when any section is missing 2+ of its 5 anchors (a single missing anchor can be interpolated from the others within the section; two or more missing means the coordinate frame for that section is untrustworthy).

### `HICOR/Services/OCR/ROI/CellLayout.swift` (new)

Pure data describing the GRK-6000 cell grid as anchor-relative offsets.

```swift
struct CellROI {
    enum Eye { case right, left }
    enum Column { case sph, cyl, ax }
    enum Row { case r1, r2, r3, avg }

    let eye: Eye
    let column: Column
    let row: Row
    let rect: CGRect   // source-image pixel coordinates
}

struct CellLayout {
    static let grk6000Desktop: CellLayout

    /// Produces all 24 required CellROI rectangles from an Anchors set.
    /// Cell positions are computed as anchor-relative offsets:
    ///   - Column X comes from the corresponding header anchor (SPH/CYL/AX).
    ///   - Row Y is interpolated from header.maxY to AVG.midY,
    ///     divided into three reading rows + AVG row.
    /// Per-eye Y origins derive from the <R> / <L> anchor vertical positions.
    func cells(given: Anchors) -> [CellROI]
}
```

Cell geometry lives in this one file. No magic numbers scattered elsewhere. Comment the rationale for each offset so future maintainers can verify against a physical printout.

### `HICOR/Services/OCR/ROI/CellROIExtractor.swift` (new)

```swift
enum CellROIExtractor {
    /// Crops each cell rectangle from `image` with `paddingFraction` expansion
    /// in both axes (default 0.1 = 10% per side). Returns paired (cell, crop)
    /// tuples in the same order as `cells`.
    static func crop(
        image: UIImage,
        cells: [CellROI],
        paddingFraction: CGFloat = 0.1
    ) -> [(CellROI, UIImage)]
}
```

Pure crop. No OCR logic.

### `HICOR/Services/OCR/ROI/CellOCR.swift` (new)

```swift
final class CellOCR {
    init(recognizer: TextRecognizer, enhancer: ImageEnhancer.Type = ImageEnhancer.self)
    func read(cell: CellROI, image: UIImage) async -> String?
}
```

Runs ML Kit on a single cell crop. Applies a column-appropriate shape check:
- SPH / CYL cells: token matches `^[-+]?\d{1,2}\.\d{2}$`.
- AX cells: integer in 1...180.

If the initial read fails the shape check, re-runs on the same crop passed through `ImageEnhancer.enhance(_:strength: .aggressive)` with a 2× upscale. Returns `nil` on a second failure — the orchestrator interprets `nil` as extraction failure for the all-or-nothing gate.

### `HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift` (new)

Orchestrator conforming to `TextExtracting`.

```swift
final class ROIPipelineExtractor: TextExtracting {
    init(fallback: TextExtracting = MLKitTextExtractor())
    func extractText(from image: UIImage) async throws -> ExtractedText
}
```

Flow:
1. `DocumentRectifier.rectify(image)` — on nil, delegate entirely to fallback.
2. `ImageEnhancer.enhance(rectified, strength: .standard)` — keep the rectified (non-enhanced) image too for retry-with-softer-preprocessing if useful.
3. `AnchorDetector.detectAnchors(in: enhanced)` — on throw, delegate to fallback.
4. `CellLayout.grk6000Desktop.cells(given: anchors)` → 24 `CellROI`.
5. `CellROIExtractor.crop(image: enhanced, cells: cellROIs, paddingFraction: 0.1)`.
6. For each `(cell, crop)` pair, `CellOCR.read(cell:image:)`. Collect into `[CellROI: String]`.
7. If any cell returned nil, throw `OCRError.incompleteCells(missing: [CellROI])` — the service layer surfaces this as a re-capture error. No partial output.
8. Assemble cell reads into `rowBased: [String]` lines matching the current `ExtractedText` contract:
   ```
   [R]
   <sph1> <cyl1> <ax1>
   <sph2> <cyl2> <ax2>
   <sph3> <cyl3> <ax3>
   AVG <sphAvg> <cylAvg> <axAvg>
   [L]
   (same pattern)
   ```
9. Return `ExtractedText(rowBased: …, columnBased: rowBased, …, revisionUsed: 0, variant: .raw)`.

Fallback contract: the fallback's output is subject to the same all-or-nothing gate as the primary path. After delegating to fallback, parse the returned `rowBased`; if it doesn't contain a complete set of 24 reading values (via a small local verifier that counts valid reading lines in each section), throw the incomplete-cells error.

## Data flow (happy path)

1. Clinician opens `CaptureView`, taps torch, aligns printout in overlay, taps shutter.
2. AVFoundation returns a raw `UIImage` (~3024×4032 on current test iPhone).
3. `ROIPipelineExtractor.extractText` runs.
4. `DocumentRectifier` warps to a ~1500×1100 rectified UIImage.
5. `ImageEnhancer` produces a high-contrast enhanced UIImage.
6. `AnchorDetector` runs ML Kit on enhanced, returns `Anchors` struct.
7. `CellLayout.cells(given:)` produces 24 `CellROI`.
8. `CellROIExtractor.crop` produces 24 small UIImage crops (~100×60 each).
9. `CellOCR.read` runs on each (×24), 23 succeed on first try, one retries with aggressive enhancement and succeeds.
10. Orchestrator assembles rowBased lines.
11. `PrintoutParser.parse(lines:)` produces a `PrintoutResult`.
12. `ConsistencyValidator` validates. Results screen appears.

**Estimated latency:** ~400ms (rectify + enhance + anchor pass) + 24 × ~60ms (per-cell ML Kit) + ~1 retry × 80ms = **~1.9s** end-to-end on a modern iPhone. Under the 3s budget with comfortable headroom.

## Error handling

**E1. `DocumentRectifier` returns nil.**
Cause: severe glare, low-contrast background, extreme capture angle, non-printout image.
Response: orchestrator delegates to `MLKitTextExtractor` fallback. Fallback output subject to same all-or-nothing gate; partial fallback output → incomplete-cells error → UI surfaces as re-capture prompt.

**E2. `DocumentRectifier` finds multiple rectangles.**
Cause: printout on a cluttered tabletop.
Response: select the rectangle with largest area whose center is inside the inner 70% of the image (biases toward the framing guide).

**E3. `AnchorDetector` throws `insufficientAnchors`.**
Cause: image too dim or out of focus even for anchor-sized text.
Response: orchestrator delegates to fallback (same as E1).

**E4. Individual cell OCR fails after retry.**
Cause: localized glare on one cell, thermal print fade, ink smear.
Response: orchestrator throws `OCRError.incompleteCells(missing:)`. No partial result written. UI surfaces a re-capture prompt with the specific cells that failed (for clinician awareness: "SPH row 2 unreadable"). Per the V1 all-or-nothing policy, any missing cell kills the extraction.

**E5. Cells disagree with AVG.**
Not addressed in this design. The existing `ConsistencyValidator` logic applies unchanged. This is a correctness concern for future work, not an input-quality concern.

**E6. Torch unavailable.**
Torch button disabled; capture proceeds without torch. On dim captures without torch the ROI pipeline is likely to produce an incomplete-cells error → re-capture prompt (not silent wrong data).

**E7. Portrait capture of landscape printout.**
`DocumentRectifier` normalizes the warped output to long-side-horizontal regardless of input orientation. Downstream components see a consistent orientation.

## Testing strategy

**Layer 1 — Unit tests (synthetic inputs, fast):**
- `DocumentRectifierTests` — rectangle selection logic, nil cases, orientation normalization.
- `ImageEnhancerTests` — pixel-value assertions at known coordinates on a flat-gray input.
- `AnchorDetectorTests` — stubbed ML Kit responses; verify `Anchors` population, verify throw on fewer than 5 anchors.
- `CellLayoutTests` — given hand-constructed `Anchors`, verify all 24 `CellROI` rectangles land at expected relative positions. **Most important suite in this work.**
- `CellROIExtractorTests` — crop dimensions, padding.
- `CellOCRTests` — shape validation per column kind; retry behavior on stub responses.
- `ROIPipelineExtractorTests` — end-to-end with stubs for every component. Happy path, rectify-nil fallback, anchor-throw fallback, any-cell-nil → incomplete-cells error.

**Layer 2 — Real-image fixture tests:**
Directory: `HICORTests/OCR/Fixtures/Images/grk6000/`. Each fixture is an actual iPhone capture with a companion `expected.json` listing the 24 human-verified reading values. Subdirectories:
- `dim_good_framing/` — refraction-room lighting, well-centered.
- `dim_tilted/` — refraction-room lighting, 10–20° tilt.
- `bright_good_framing/` — baseline sanity.
- `dim_poor_framing/` — expected to trigger re-capture error.

Test passes iff all 24 cell values match the expected set (or, for `dim_poor_framing`, iff the pipeline throws `incompleteCells`). Per the existing `feedback_test_fixtures_real_data.md` memory, fixture images and expected JSON values come from actual captures, not invented data.

**Layer 3 — On-device validation (gate for declaring work done):**
1. Install on the iPhone used for prior testing.
2. Capture 10 distinct photos of the GRK-6000 printout under clinically realistic conditions (refraction-room lighting, torch on, one-handed phone use).
3. Pass criteria:
   - ≥9 of 10 captures produce all 24 readings with values matching the physical printout.
   - 0 of 10 captures produce incorrect readings. (Re-capture prompts are acceptable; wrong silent values are not.)
4. One intentional bad capture (severe tilt, partial crop, or selfie misfire) must produce a re-capture prompt rather than a partial result or a crash.
5. Add two successful captures to the fixture corpus as regression guards.

**Regression — unchanged suites that must stay green:**
- `OCRServiceTests` (6 tests) — tests the service layer through `TextExtracting`; ROI pipeline is a new conformer.
- `VisionTextExtractorTests` (10 tests) — tests fallback path internals.
- All parser/normalizer/validator suites — operate on row-based strings, unaffected.

## Files changed

**New:**
- `HICOR/Views/CaptureView.swift`
- `HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift`
- `HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift`
- `HICOR/Services/OCR/ROI/AnchorDetector.swift`
- `HICOR/Services/OCR/ROI/CellLayout.swift`
- `HICOR/Services/OCR/ROI/CellROIExtractor.swift`
- `HICOR/Services/OCR/ROI/CellOCR.swift`
- `HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift`
- Seven matching unit-test files: one per new component (`DocumentRectifierTests`, `ImageEnhancerTests`, `AnchorDetectorTests`, `CellLayoutTests`, `CellROIExtractorTests`, `CellOCRTests`, `ROIPipelineExtractorTests`).
- Fixture corpus under `HICORTests/OCR/Fixtures/Images/grk6000/`.

**Modified:**
- `HICOR/Views/PhotoCaptureView.swift` — swap `CameraPickerView` for `CaptureView`.
- `HICOR/Services/OCR/OCRService.swift` — default extractor becomes `ROIPipelineExtractor(fallback: MLKitTextExtractor())`; add `OCRError.incompleteCells(missing: [String])` case to the existing `OCRError` enum.
- `HICOR/Views/AnalysisPlaceholderView.swift:225-237` — extend the `humanReadable(_ error:)` switch to handle the new `incompleteCells` case with a re-capture prompt that lists which sections failed (e.g., "Couldn't read right-eye SPH row 2. Retake the photo.").

**Deleted:**
- `HICOR/Views/CameraPickerView.swift` — replaced by `CaptureView`.

**Unchanged (critical — this is the point of the protocol boundary):**
- `HICOR/Services/OCR/PrintoutParser.swift`
- `HICOR/Services/OCR/DesktopFormatParser.swift`
- `HICOR/Services/OCR/HandheldFormatParser.swift`
- `HICOR/Services/OCR/ReadingNormalizer.swift`
- `HICOR/Services/OCR/ConsistencyValidator.swift`
- `HICOR/Services/OCR/MLKitTextExtractor.swift` — retained as fallback.
- `TextExtracting` protocol, `ExtractedText` struct, `TextBox` struct.

## Risks

- **Rectangle detection on dim backgrounds.** `VNDetectRectanglesRequest` can miss low-contrast edges. Mitigated by the framing guide (clinicians fill the frame, leaving visible contrast between printout and background) and by the fallback to `MLKitTextExtractor`.
- **Anchor OCR failure on the same captures that fail cell OCR.** Plausible but less likely: anchors are larger and bolder than data cells. If anchor detection fails often in practice, escalation is auto-capture (Option C in the brainstorm) which would rectify earlier in the stack.
- **Cell-layout calibration drift.** GRK-6000 printer paper sometimes shifts. The anchor-relative offset design absorbs small shifts; large shifts would require fixture captures to re-tune the offset table in `CellLayout`. Design mitigates but does not eliminate this.
- **PD extraction.** PD is outside the 24-cell gate and keeps its existing manual-entry fallback. The ROI pipeline does not attempt PD. Acceptable because PD failure is already a handled UI state.

## Rollback

- One-line revert: `OCRService.swift` default extractor changes back to `MLKitTextExtractor()`.
- `ROIPipelineExtractor` and supporting files stay in the repo dormant; remove in a follow-up if abandoning.
- `CaptureView` is an independent change; if it causes capture issues, revert to `CameraPickerView` without touching the OCR layer.

## Known future items

- **Single-eye / partial-measurement relaxation** (post-May 2026). Design it as an explicit "measurement refused" per-eye marker captured at scan time, not implicit tolerance of missing cells.
- **Handheld autorefractor support** (targeting July 2026 trip). The `CellLayout` abstraction is designed to accept a second layout variant; add `CellLayout.handheld` when real captures are available.
- **Auto-capture escalation** (if manual shutter proves insufficient). Option C in the brainstorm: live rectangle detection + stability lock + auto-shutter. Not needed unless field testing shows the manual shutter workflow can't reach the accuracy bar.
