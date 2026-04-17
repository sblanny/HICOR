# HICOR OCR Pipeline Independent Review (Codex)

Date: 2026-04-16  
Reviewer: Codex (independent second opinion)

## Scope Reviewed

- `HICOR/Services/OCR/VisionTextExtractor.swift`
- `HICOR/Services/OCR/PrintoutParser.swift`
- `HICOR/Services/OCR/HandheldFormatParser.swift`
- `HICOR/Services/OCR/DesktopFormatParser.swift`
- `HICOR/Services/OCR/ReadingNormalizer.swift`
- `HICOR/Services/OCR/ConsistencyValidator.swift`
- `HICOR/Services/OCR/OCRService.swift`
- `HICOR/Views/AnalysisPlaceholderView.swift`
- `HICORTests/OCR/*` and available OCR fixtures

## Executive Assessment

The OCR stack has some genuinely good defensive ideas (format-specific parsers, plausibility gates, SPH-only handling, consistency checks), but it is currently brittle in exactly the places that decide whether Vision output is usable. Most reliability losses are not from one catastrophic bug; they come from a chain of small design choices that compound:

1. Vision request is pinned to an older revision and has a narrow, static preprocessing strategy.
2. OCR normalization mutates non-numeric text globally, creating format-detection and token-corruption risk.
3. Reconstruction is geometry-only with fixed thresholds and no confidence/semantic reconciliation.
4. Parsing and pipeline orchestration are duplicated across service and view layers.
5. Tests are strong at parser unit level but weak at end-to-end OCR realism (noise, skew, blur, crop, mixed orientation, fragmented tokens).

Bottom line: this implementation can pass current tests while still failing often on real thermal-paper captures.

---

## 1) Code Quality Assessment

### What is solid

- **Separation of concerns is mostly good**: extractor, parser, normalizer, validator, and coordinator are conceptually separated.
- **Plausibility constraints are directionally correct** (`ReadingPlausibility` blocks obvious garbage such as SPH=90).
- **SPH-only support is clinically thoughtful** (placeholder cyl/ax and downstream exclusion in cyl spread checks).
- **Column reconstruction tests cover some real failure patterns** (uneven column heights, single-eye sections).
- **Explicit error taxonomy** in `OCRService` is useful for UX and triage.

### What is suspect

- **Normalization is too blunt**: `ReadingNormalizer.normalizeOCRString` replaces `O/o/l/I/S/B` globally. This can silently alter headers/markers/labels and increase false positives/false negatives in format detection and parsing.
- **`allowQualityMarker` is effectively ignored** in `ReadingLineShape.matches`; desktop calls pass `false`, but regex still accepts AQ/E suffix.
- **Heavy `print` logging in parsing/validation path** risks performance/noise and exposes implementation details in release logs unless compile-gated.
- **Ambiguous section slicing** in desktop parser (`sliceSection`) can prematurely terminate when marker-like text appears in noisy lines.

### Likely broken in production while still passing tests

- **Vision revision lock**: extractor hardcodes `VNRecognizeTextRequestRevision3` for iOS 16+, which may underperform newer revisions available on iOS 17/18.
- **Fixed geometric thresholds** (`rowTolerance = 0.02`, `columnGapThreshold = 0.08`) likely fail across different zoom levels, crop extents, and perspective distortion.
- **Pipeline duplication drift**: `OCRService.parseBest` and `AnalysisPlaceholderView.runOCR` implement similar but not identical selection logic. This creates behavioral divergence that tests can miss because most tests hit service/parser units directly.

---

## 2) OCR Strategy Analysis (Vision + preprocessing)

### Vision configuration

Current config:
- `.accurate` recognition level
- `recognitionLanguages = ["en-US"]`
- `usesLanguageCorrection = false` (good for numeric OCR)
- `customWords` with ophthalmic tokens
- `minimumTextHeight = 0.01`
- forced `revision = Revision3` on iOS 16+

Assessment:
- **Good call**: disabling language correction is correct for numeric medical printouts.
- **Weak call**: forced revision 3 is not optimal for newer iOS versions; it prevents benefiting from Apple’s later OCR improvements.
- **Mixed value**: custom words help headers/labels but do little for numeric token stability (the real pain point).
- **Potential recall loss**: fixed minimum text height may drop fine thermal glyphs when printout occupies less image area.

### Preprocessing for thermal paper

Current steps:
- upscale x2
- desaturate + contrast boost + brightness shift
- unsharp mask

Assessment:
- This is a **reasonable first-pass**, but not robust for thermal-paper variability.
- Missing key thermal-specific tactics:
  - local/adaptive thresholding (not just global contrast)
  - denoise tuned for speckle/streak artifacts
  - morphology (close/open) for broken strokes
  - deskew/perspective correction prior to OCR
  - multi-pass OCR with different preprocess variants and voting
- One fixed filter chain is unlikely to generalize across shadowed, overexposed, faded, and low-contrast receipts.

---

## 3) Parser Robustness

### Strengths

- Explicit desktop/handheld routing with fallback heuristics.
- Strict reading-line shape gate prevents many axis-fragment false parses.
- Plausibility filters reduce catastrophic numeric poisoning.
- Handheld parser correctly carries star-line confidence when present.

### Fragility points

- **Format detection is brittle**:
  - desktop depends on `AVG`, `GRK`, or `HIGHLANDS OPTICAL`
  - handheld depends on `-REF-`/`REF-` or `*` + bracket markers
  - OCR variants like `A VG`, `- R E F -`, bracket damage, or header dropout can misroute.
- **Global OCR normalization may alter markers** before parsing, changing detection outcomes unpredictably.
- **Column reconstruction assumes nearest-column grouping is stable** with fixed gap threshold; this breaks on uneven horizontal scaling or partial column capture.
- **Row reconstruction merges by y-distance only**; near-horizontal drift or perspective warp can interleave adjacent lines.
- **Star-line parsing accepts any numeric 4th token as confidence if 1...9**; no stronger structural validation.
- **Desktop PD regex only supports integer PD** and narrow formats; decimal or split-token PD variations are missed.

### Row-vs-column strategy soundness

The dual-strategy concept is good. The implementation is incomplete because strategy selection is based mostly on reading count rather than parse confidence/consistency score. There is no arbitration on:
- plausibility density
- marker continuity
- expected section completeness
- token confidence aggregation

As a result, the system can pick the “less wrong” parse by accident.

---

## 4) Test Coverage Gaps

Current tests are parser-centric and valuable, but coverage is skewed toward clean synthetic lines/fixtures. Missing high-impact scenarios:

- **No image-level OCR regression suite** using real or realistically degraded thermal photos.
- **No systematic fuzzing for token fragmentation** (e.g., broken decimal points, split sign/value across observations).
- **No deskew/perspective stress tests** with rotated/cropped printouts.
- **No low-light/high-glare/shadow variants** for preprocessing validation.
- **No tests for malformed but near-valid headers/markers** (`[R` without `]`, `A VG`, `P D`).
- **No confidence-threshold behavior tests** for star line reliability and downstream weighting.
- **No cross-device camera variability fixtures** (different iPhone sensor/sharpening pipelines).
- **No explicit tests that compare row-based vs column-based parse quality scoring**, because quality scoring does not yet exist.

Missing fixture categories (recommended):
- blurred thermal paper
- faint/faded print
- skewed/perspective-distorted capture
- partial crop (top or bottom clipped)
- mixed OCR breakage (e.g., decimal missing in one column only)
- corrupted markers with otherwise parseable readings
- out-of-order observations resembling real Vision output

---

## 5) Alternative Approaches Recommended

## A) Better Vision-first architecture (recommended immediate path)

- Use **latest supported Vision revision by default** and only fall back when needed.
- Run **multi-pass OCR**:
  1) raw image
  2) high-contrast binarized image
  3) denoised + sharpened image  
  Then merge candidates by confidence + plausibility scoring.
- Build **line reconstruction with robust clustering** (adaptive DBSCAN-like grouping in normalized coords) instead of fixed hard-coded thresholds.
- Add **parse confidence scoring** and choose row/column parse by score, not just count.

## B) Hybrid OCR + template constraints

- Use known printout structure as a weak template:
  - detect anchor tokens (`[R]`, `[L]`, `AVG`, `PD`, `*`)
  - infer expected row/column zones relative to anchors
  - reject token placements violating layout priors
- This dramatically improves stability for fixed-format medical slips.

## C) Alternative OCR engines

- **Google ML Kit (on-device text recognition)**: often strong on mobile capture noise, easier confidence handling; worth A/B testing.
- **Tesseract**: flexible but generally weaker out-of-the-box on mobile thermal receipts unless heavily tuned.
- **PaddleOCR**: powerful but higher integration complexity/size/perf burden on iOS.

Recommendation: run a benchmark bake-off on the same fixture/photo corpus. Do not switch engines blindly.

## D) Custom ML model path (longer-term)

- Train a detector/recognizer stack (or fine-tuned OCR head) on labeled autorefractor slips.
- Highest potential ceiling, but requires dataset, labeling, MLOps, and careful on-device performance budget.
- Good for long-term mission-critical reliability, not first-line short-term fix.

---

## 6) Ranked Actionable Fixes (by expected improvement)

### 1. Replace hardcoded Vision revision and add adaptive fallback (highest ROI)

- Default to latest available request revision on runtime OS.
- If parse confidence is low, retry with prior revision(s).
- Expected impact: **high**.

### 2. Introduce multi-pass preprocessing + parse-score arbitration

- Generate 2-4 preprocessing variants and run OCR on each.
- Score parses using plausibility, section completeness, marker continuity, and confidence.
- Select best score, not first parse with nonzero reading count.
- Expected impact: **high**.

### 3. Stop global character substitution; normalize contextually

- Apply OCR correction only to numeric token candidates, not full lines.
- Keep raw line for marker detection and structural parsing.
- Expected impact: **high** (reduces silent corruption).

### 4. Unify pipeline logic in one orchestrator

- Consolidate `parseBest` logic into a single code path used by both service and UI flow.
- Return structured diagnostics from service, not duplicated parse attempts in view.
- Expected impact: **medium-high** (behavior consistency, fewer hidden regressions).

### 5. Replace fixed geometric thresholds with adaptive clustering

- Compute row/column groupings from observation distribution (not constants only).
- Include fallback for heavily skewed/perspective-distorted captures.
- Expected impact: **medium-high**.

### 6. Expand test corpus to real-world capture failures

- Add photo fixtures and synthetic degradations.
- Add regression tests for marker corruption and mixed token fragmentation.
- Expected impact: **medium** (critical for preventing backslide).

### 7. Gate verbose parser logging and add metrics instrumentation

- Compile-gate debug prints.
- Capture structured OCR metrics (parse score, failure reason, section completeness).
- Expected impact: **medium** (operational visibility).

### 8. Strengthen format detection and PD extraction

- More tolerant marker regexes and alternate tokenization strategies.
- PD parsing for decimal and split-token variants.
- Expected impact: **medium-low**.

---

## What I Would Expect Claude to Recommend vs This Review

Given the current code style, I would expect Claude-generated recommendations to emphasize incremental parser regex hardening and additional guard clauses. That is useful, but insufficient.

Main differences in this review:

1. **Stronger emphasis on OCR-system design** (multi-pass preprocessing, score-based arbitration, adaptive geometry), not only parser tweaks.
2. **Direct criticism of global normalization strategy** as a root reliability hazard.
3. **Direct criticism of revision pinning** as a likely hidden performance regression on modern iOS.
4. **Recommendation for empirical engine bake-off** (Vision vs ML Kit) before further parser complexity growth.
5. **Call to remove duplicated orchestration logic** between service and view as a reliability risk, not just code style concern.

---

## Final Verdict

The current pipeline is a respectable prototype with meaningful defensive parsing, but not yet a production-reliable OCR system for thermal autorefractor slips. Reliability issues are expected under realistic capture conditions, and current tests are not representative enough to catch many of those failures.

If only three changes are made immediately, they should be:
- latest Vision revision + fallback strategy
- multi-pass OCR with scoring-based parse selection
- contextual (token-level) normalization instead of global character substitution

Those three alone should materially improve extraction consistency without requiring a full OCR-engine migration.
