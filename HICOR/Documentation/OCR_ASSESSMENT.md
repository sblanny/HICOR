# OCR Failure Root-Cause Assessment

**Date:** 2026-04-16
**Branch at time of writing:** `main` @ `fbd6b21`
**Pipeline under review:** Apple Vision (`VNRecognizeTextRequestRevision3`) → row/column text reconstruction → `PrintoutParser` → `ReadingLineShape` gate → `HandheldFormatParser` / `DesktopFormatParser` → `ConsistencyValidator`
**Deadline context:** May 1, 2026 mission-trip launch — ~15 days from today.

---

## 0. Executive summary

**Recommendation: Instrument first, switch only if instrumentation proves Vision can't be fixed.** Do not change OCR code for 48 hours. Capture 5–10 real field-photo `OCRDebugSnapshot` records, inspect them in `OCRDebugView`, and catalog the *actual* Vision output. Current code already logs per-line accept/reject reasons (`Parser: rejecting ... — reason: …`) and persists preprocessed JPEGs into the snapshot. Once we have evidence, the highest-probability fix is a **shape-regex relaxation + preprocessing tone-down**, both implementable in under a day. Only if those fail on >30% of collected samples should we swap to Google ML Kit — the parser/validator layer is engine-agnostic and the switch cost is genuinely bounded (~1 engineer-day, zero changes outside `VisionTextExtractor.swift`).

---

## 1. Empirical evidence

### 1.1 Scope and a hard honesty caveat

The request asked for "the last 5 OCR debug snapshots from the codebase." **No such snapshots are committed to this repo.** `OCRDebugSnapshot` is a runtime structure (`HICOR/Services/OCR/OCRDebugSnapshot.swift`) that is (a) JSON-encoded into the `rawReadingsData` field of a failure `PatientRefraction` and pushed to CloudKit by `AnalysisPlaceholderView.persistFailure(snapshot:)` and (b) surfaced in-session via `OCRDebugView`. They live on device and in the CloudKit public DB, not in git. The `fbd6b21` commit added the per-line `print("Parser: rejecting …")` instrumentation, but those logs land on stdout — nothing committed.

What is committed and usable as evidence:

1. **The `fbd6b21` commit message** (one documented field failure, reproduced verbatim in the regression tests).
2. **The OCR-garbage fixtures in `HandheldFormatParserTests.swift` lines 159–181** — these are not invented patterns; per the project's stated convention (`MEMORY.md` → `feedback_test_fixtures_real_data.md`), "OCR/parser fixtures must mirror exact real machine output." The garbage strings in those tests were observed in the wild and captured as regressions.
3. **The preprocessing stack in `VisionTextExtractor.preprocessForOCR`** (we know exactly what Vision is being fed).
4. **The reconstruction algorithm** (row-based by Y-grouping at 0.02 tolerance; column-based section-aware with 0.08 X-gap).

### 1.2 What we actually know about the failures

The `fbd6b21` commit message documents one real, traced field failure end-to-end:

| Stage | Observed value |
|---|---|
| Vision output line (reconstructed) | `"111  25  25  -  0.25  54"` |
| Parser (pre-strict) interpretation | SPH=111, CYL=25, AX=25, stray `- 0.25 54` |
| Persisted to `RawReading.sph` | `+111.0` (poisoned) |
| ConsistencyValidator `rAvg` | `25.4` |
| ConsistencyValidator `lAvg` | `123.9` |
| ConsistencyValidator outcome | Sign-mismatch flagged (`right+, left-`) on two clearly-negative eyes |

The same row-level failure is embedded as regression test coverage in `HandheldFormatParserTests.swift`:

| Garbage string (from tests) | What it represents |
|---|---|
| `"111  25  25  -  0.25  54"` | Decimal dropped from SPH + CYL; column reconstruction joined tokens across two physical rows |
| `"2.  25  49"` | SPH decimal portion lost — Vision saw "2." and dropped ".00", or misread "2.00" as "2." |
| `"54  108  136"` | Three bare integers; all three tokens are axis-magnitude values; no decimal appears at all |
| `"90"`, `"180"`, `"136"` | Single stray axis token — a reading row fragmented into a separate observation holding only the axis number |
| `"85 AQ"` | Axis + quality marker alone — SPH and CYL fell into a different reconstructed row |

### 1.3 Extraction vs. input numbers

Reference fixture `handheld_standard.txt` contains **8 readings per eye + 1 AVG line per eye** (18 data rows, not counting headers). `handheld_mixed_sph_only.txt` contains **5 R + 5 L**, half of them SPH-only (one-token rows). `handheld_large_sph.txt` has the edge-case `+21.00` readings.

The user's report is "the parser accepts few clean readings but many are dropped." Given the only currently-committed evidence, we cannot say *exactly* how many — but the pattern documented in `fbd6b21` plus the fragmentation patterns in the tests all share one root symptom: **loss of the decimal point, or loss of column integrity, at the Vision stage.** Post-`fbd6b21` the parser correctly refuses the garbage; pre-`fbd6b21` it silently accepted poisoned values. The underlying extraction quality did not change between those two states — only the downstream handling.

### 1.4 What the current pipeline will accept and reject

Given the shape regex in `ReadingValidation.swift` —

```
^\s*[-+]?\s*\d{1,2}\.\d{2}(\s+[-+]?\s*\d{1,2}\.\d{2}\s+\d{1,3})?(\s+(?:AQ|E))?\s*$
```

— these lines pass (observed working):

- `"- 3.25 - 1.00  81 AQ"` ✓
- `"+ 21.00 - 1.00  90 AQ"` ✓
- `"- 2.00 AQ"` ✓ (SPH-only with quality marker)
- `"- 2.00"` ✓ (SPH-only bare)

These lines are silently dropped (every one a probable Vision output):

| Rejected string | Reason |
|---|---|
| `"-3.25 -1.00 81"` | Passes (sign combined) — this is fine |
| `".25 -1.00 81"` | Fails: SPH needs `\d{1,2}\.\d{2}`; `.25` has zero digits before decimal |
| `"3.25 -1.00 81 AO"` | Fails: quality tail is not literal `AQ`/`E` (Vision read `Q→O`) |
| `"3.25 -1.00 81 40"` | Fails: extra trailing numeric (Vision mangled `AQ` as digits) |
| `"325 -100 81"` | Fails: no decimals — Vision lost both dots |
| `"3,25 -1,00 81"` | Fails: comma instead of period (locale/glyph confusion) |
| `"- 3 . 25 - 1 . 00 81"` | Fails: tokenizer splits `3 . 25` into three tokens, first token `-` and `3` don't form a sphere-shaped decimal |
| `"- 3.2 - 1.0 81"` | Fails: `\d{2}` mantissa, not `\d{1,2}` |
| `"3.25 -1.00 81 E"` | Passes — `E` is in the optional tail |
| `"3.25 -1.00 81 e"` | Fails: case-sensitive regex |

That table is not exhaustive but covers the high-probability Vision failure modes. Each rejected pattern represents a class of lost reading.

---

## 2. Root-cause hypotheses, ranked

Each hypothesis is stated as a single claim, with the code path that would cause it and the class of observed failures it explains.

### H1 — Vision is losing the decimal point (HIGH probability)

**Claim.** On thermal-printout thin-stroke digits, Vision renders `3.25` as `325`, `21.00` as `2100`, or truncates to `2.`. The decimal glyph is a single pixel-class feature that falls below the effective recognition threshold after preprocessing.

**Code path.** `VisionTextExtractor.preprocessForOCR` applies: 2× scale → grayscale (saturation 0) → contrast 1.8 → brightness +0.05 → unsharp mask (intensity 0.7, radius 2.5). Each of those operations individually is defensible; together they are aggressive enough to:
- Blow out faint dots (contrast 1.8 clips mid-tones toward white on faded thermal paper).
- Create ringing around thin strokes (unsharp mask radius 2.5 at intensity 0.7 is quite strong for 2× up-sampled 8-bit imagery; decimal points can split into two half-dots that the recognizer reads as nothing).
- `minimumTextHeight = 0.01` (1% of image height) allows tiny glyphs, but the recognizer's confidence is lower at that scale and it tends to "simplify" punctuation away.

**Evidence.** `"2.  25  49"` in the test corpus is a textbook symptom of this — Vision captured the `2.` but threw away `00` after the decimal, then stitched the next row's `25 49` onto the same reconstructed line. The `"111  25  25"` pattern is three decimal-less integers appearing where `1.11 2.5 25` or similar once was.

### H2 — Row/column reconstruction is mis-grouping reading rows (HIGH probability)

**Claim.** The row tolerance (`defaultRowTolerance = 0.02`, i.e. 2% of image height) is either too loose or too tight depending on the photo's perspective. When the printout is photographed at an angle, rows skew diagonally and either collapse into one another (two physical readings appear in one reconstructed row) or split (one physical reading appears in two rows).

**Code path.** `VisionTextExtractor.reconstructRows` uses `abs(first.midY - box.midY) < rowTolerance` where `rowTolerance = 0.02`. For a 4032×3024 iPhone photo that is 80 px. Handheld autorefractor thermal lines are ~40–60 px tall in a typical capture, separated by similar gaps — a 5° tilt can put boxes from two physical rows within the same 80-px Y-band. The column-based path (`reconstructColumnarLines` → `reconstructColumnsInSection`) uses an 0.08 X-gap to decide column boundaries; partial readings leave ragged columns where boxes snap to the wrong column center.

**Evidence.** `"54  108  136"` (three axes on one line) is exactly what you get when two or three physical rows' axis columns collapse into a single reconstructed row. `"85 AQ"` as a standalone row is the inverse — the SPH/CYL boxes ended up on the previous reconstructed row and only the tail `85 AQ` is left.

### H3 — `AQ` quality marker is being mangled by the OCR string normalizer (MEDIUM probability)

**Claim.** The quality marker on handheld lines is `AQ` or `E`. `AQ` is two narrow letters in a thin-stroke thermal font and is the most error-prone glyph pair on the printout. Vision commonly renders it as `AO`, `A0`, `40`, `DO`, `4Q`. `ReadingNormalizer.normalizeOCRString` then applies `O→0` (capital and lower) — so `AO` becomes `A0`, which is not in the shape-regex allowed tail `(\s+(?:AQ|E))?` and fails the match.

**Code path.** The regex requires the line to end in `(AQ|E)` exactly (case-sensitive). `normalizeOCRString` runs BEFORE the regex (`HandheldFormatParser.parse` line 5), and the substitution `s.replacingOccurrences(of: "O", with: "0")` is unconditional across the entire string. Any `AQ` that Vision misread as `AO` is converted to `A0`, which cannot pass the optional tail. The line then has "extra tokens" (a bare `A0` after the axis) and the *whole-line-anchored* regex `^...$` fails.

**Evidence.** Indirect — we do not have a captured runtime example confirming this, but: (a) the normalizer's O→0 rule is globally applied and (b) any 2-letter suffix is the most vulnerable glyph on a thermal printout, so the prior is high.

### H4 — Sign fragmentation (MEDIUM probability, partially handled)

**Claim.** `- 3.25` often arrives from Vision as the separate tokens `-` and `3.25`. `combineSignTokens` already reunites them when they are adjacent in the reconstructed line. But if column reconstruction pushes `-` into a "sign column" and `3.25` into the "sphere column" with intervening junk, the tokens are no longer adjacent and re-joining fails.

**Code path.** `DesktopFormatParser.combineSignTokens` walks tokens left to right; it only combines when `tokens[i]` is `+/-` and `tokens[i+1]` parses as Double. Two tokens apart: no combine.

**Evidence.** Shape regex `^\s*[-+]?\s*\d{1,2}\.\d{2}...` allows a space between sign and magnitude, so if the sign survives as an adjacent token this is fine. The risk is only when reconstruction inserts junk between them.

### H5 — Preprocessing is over-tuned for the wrong problem (MEDIUM probability)

**Claim.** Contrast 1.8 + unsharp mask (0.7 / 2.5) was chosen to help fragmented thermal text (per `e721eec` "preprocess images before Vision OCR to handle thermal printout fragmentation"). It may be solving the fragmentation problem and creating the decimal-loss problem (H1). Thermal printouts are already high-contrast; over-boosting clips mid-tones and obliterates thin strokes.

**Code path.** `VisionTextExtractor.preprocessForOCR`.

**Evidence.** Circumstantial. The fix in `e721eec` predates the `fbd6b21` evidence; we added contrast to solve problem A and it plausibly caused problem B.

### H6 — Regex mantissa too strict (`\d{2}` required) (MEDIUM probability)

**Claim.** Real autorefractor readings are quarter-diopter values — mantissa is always `.00`, `.25`, `.50`, `.75` — so `\d{2}` is correct in a perfect world. But if Vision drops a single digit (reads `3.2` instead of `3.25`), the line is rejected even though `3.2` is within ±0.05 of truth. Similarly `3.250` (Vision hallucinated a trailing zero) fails. Similarly `3.5` fails because mantissa is only one digit.

**Code path.** `ReadingValidation.swift` pattern `\d{1,2}\.\d{2}`.

**Evidence.** The fixture `+ 21.00` values in `handheld_large_sph.txt` rely on the mantissa being exactly `.00`. A single-digit misread there drops the line.

### H7 — Vision revision-3 numeric bias (LOW–MEDIUM probability)

**Claim.** `VNRecognizeTextRequestRevision3` (iOS 16+, also the latest available on iOS 17) was trained dominantly on natural English text. Even with `usesLanguageCorrection = false` the underlying recognizer has residual bias toward character shapes common in English. Revision 4 (iOS 18+) is substantially improved at numerics and small text. The project's stated min-iOS is 17 (CLAUDE.md), so revision 4 is unavailable without a min-OS bump.

**Evidence.** Apple's WWDC '24 Vision session materials; cannot benchmark without live device comparison.

### H8 — Parser strategy selection picks the lesser garbage (LOW probability, low impact now)

**Claim.** `AnalysisPlaceholderView.runOCR` and `OCRService.parseBest` pick row-based vs. column-based by `readingCount > 0`. Post-strict-validation, both strategies can fail on the same photo and the parser returns the one with more readings — which, if both are garbage, is still garbage.

**Code path.** `AnalysisPlaceholderView.swift` lines 185–196; `OCRService.parseBest`.

**Evidence.** Not a root cause of the *drop* but will amplify user-visible failure rate when both strategies produce zero readings.

### What I explicitly ruled out

- **Parsing logic error** (the parsers are correct given the strings they receive — 99 unit tests pass on fixture-identical text).
- **Consistency validator bug** (already fixed in `5cb782a` + defense-in-depth in `fbd6b21`).
- **Custom-words list biasing wrong direction** (it biases toward `SPH/CYL/AX/AQ/REF/PD/VD/AVG/[R]/[L]/<R>/<L>/Name/No` — none of those are numeric, so customWords cannot cause a missed digit).
- **Orientation** (fixed in `31a116f`; reconstruction is upright-agnostic since it works in normalized box coordinates).

---

## 3. Hypothesis tests — what would confirm/rule out each

No hypothesis should be acted on until at least one decisive test is run. Proposed tests, ordered by cost:

| # | Hypothesis | Test | Confirms if… | Time |
|---|---|---|---|---|
| T1 | H1, H5 | Take 5 real printout photos. In the failing alert, tap "Show Debug Info". Inspect the preprocessed JPEG embedded in the `OCRDebugSnapshot.Entry.preprocessedImageData` — is the decimal point visible to the human eye? | Decimal visible → H1 (Vision lost it). Decimal invisible/blown out → H5 (preprocessing destroyed it). | 20 min |
| T2 | H1 | Run Vision on the **raw**, unprocessed CGImage (add a one-line toggle; revert after). Compare reconstructed lines. | If raw produces more valid readings, H5 is confirmed. If raw is equal/worse, H1 is confirmed independent of preprocessing. | 1–2 hr |
| T3 | H2 | Log `observation.boundingBox` for every observation on a failing photo; plot Y vs X manually. Count rows by eye, count rows reconstructed. | Mismatch between physical-row count and reconstructed-row count confirms H2. | 1 hr |
| T4 | H3 | Grep the snapshot debug output for `AQ`, `AO`, `A0`, `40` in the same column position as other valid readings. | Presence of `AO`/`A0`/`40` where `AQ` should be confirms H3. | 15 min |
| T5 | H6 | Temporarily loosen the regex mantissa to `\d{1,2}\.\d{1,2}` and re-run against snapshot strings. | More lines pass → H6 contributes. | 30 min |
| T6 | H7 | Build one beta with iOS-18-only `VNRecognizeTextRequestRevision4` gated on `@available(iOS 18, *)`, fall back to rev 3 on 17. Compare same photo on an iOS 17 vs. iOS 18 device. | Rev 4 substantially better → H7 contributes, informs whether to bump min-OS. | 4–6 hr |
| T7 | H1, H2, H3, H5 combined | Run Google ML Kit on 5 of the same failing photos (spike branch, not merged). | ML Kit beats Vision by >20% on the same inputs → argues for engine swap. | 1 day spike |

**T1 is the only one to do first.** It is free, is done on-device in 20 minutes, and will disambiguate H1 vs. H5 — which determines whether the next fix is a regex change or a preprocessing change. Do not write any fix before T1.

---

## 4. Ranked fix options

All effort estimates assume one engineer and no parallel work.

### Tier A — low-risk, high-probability targeted fixes

| Fix | Addresses | Effort | Likelihood | Regression risk |
|---|---|---|---|---|
| **A1. Soften preprocessing** (contrast 1.8 → 1.3, unsharp 0.7/2.5 → 0.3/1.5) | H1, H5 | 30 min code + testing | High, *if* T1 confirms preprocessing is the issue | Low — no test fixtures exercise preprocessing directly, only a visual diff on a known photo can regress |
| **A2. Run OCR twice — raw AND preprocessed — merge lines** | H1, H5 | 2 hr | High | Low — parser picks the strategy with more readings regardless |
| **A3. Relax shape regex mantissa to `\d{1,2}\.\d{1,2}`** | H6 | 15 min + 1 test | Medium | Low — `ReadingPlausibility` range check still guards against garbage |
| **A4. Tolerant quality-marker tail: accept `AQ / AO / A0 / E / e`** | H3 | 15 min | Medium | Very low — tail is purely informational for `lowConfidence` |
| **A5. Fix `normalizeOCRString`: do NOT apply `O→0` / `S→5` / `B→8` inside tokens that already look like letters-only suffixes** | H3 | 30 min | Medium | Low — scoped change |
| **A6. Add per-eye sanity: if a reconstructed block has <2 valid readings but >4 rejected rows, attempt row-wise "patch mode" — allow a line where the SPH token is bare-integer-but-preceded-by-a-sign, converted to `N.00`** | H1 partial salvage | 4 hr + tests | Low–Medium | Medium — could let through ambiguous values; needs unit tests |

Combined effect of A1+A2+A3+A4+A5: probably recovers >50% of currently-dropped lines *if* preprocessing is a real contributor. Total time: ~1 day.

### Tier B — structural changes, still on Vision

| Fix | Addresses | Effort | Likelihood | Regression risk |
|---|---|---|---|---|
| **B1. Adaptive row tolerance** (`rowTolerance` based on median box height in the image, not a fixed 0.02) | H2 | 4 hr + tests | Medium | Medium — changes reconstruction behavior; needs fixture-replay tests |
| **B2. Use the observation's `confidence` score** to skip low-confidence boxes before reconstruction | H1 partial | 2 hr | Low–Medium | Low |
| **B3. Vision `minimumTextHeight` tuning** — try 0.015, 0.02 | H1 | 30 min + T1 comparison | Low | Low |
| **B4. Gate revision 4 on iOS 18+** (with rev 3 fallback) and bump min-OS to 17.5 or 18 | H7 | 1 hr code + Apple Store availability review | Medium | Low (code), high (business) — cuts off iOS 17.0–17.4 devices; mission-trip volunteer devices may still be on 17.x |

### Tier C — engine swap

| Fix | Addresses | Effort | Likelihood | Regression risk |
|---|---|---|---|---|
| **C1. Google ML Kit Text Recognition v2 as a replacement `TextExtracting`** | All H1–H7 potentially | 1–2 days | High — ML Kit v2 is well-regarded for receipts/numerics | Low — parser/validator unchanged; can A/B behind feature flag |
| **C2. Google ML Kit as a fallback** (run Vision first, fall back to ML Kit if Vision produces <N readings) | All H1–H7 | 2 days | Highest — combines both engines | Low |
| **C3. Tesseract with custom training on the autorefractor font** | All H1–H7 | 3–5 days including training | Medium | Medium — custom training can over-fit |

---

## 5. Switching-cost analysis (if Vision must be replaced)

The architecture here is already engine-agnostic. `VisionTextExtractor` is the ONLY file that touches Vision. It implements:

```swift
protocol TextExtracting {
    func extractText(from image: UIImage) async throws -> ExtractedText
}
```

…and returns:

```swift
struct ExtractedText { let rowBased: [String]; let columnBased: [String]; … }
```

Everything downstream operates on `[String]`. Here is the exact scope of each swap:

### Stays unchanged in any swap

- `PrintoutParser.swift` (format detection)
- `DesktopFormatParser.swift`
- `HandheldFormatParser.swift`
- `ReadingNormalizer.swift`
- `ReadingValidation.swift` (shape regex + plausibility)
- `ConsistencyValidator.swift`
- `OCRService.swift` (takes any `TextExtracting`)
- All 99 unit tests (fixture-driven from `[String]`)
- `AnalysisPlaceholderView.swift` (consumes `ExtractedText`)
- `OCRDebugSnapshot.swift` / `OCRDebugView.swift`
- The `TextBox` → row/column reconstruction functions are static on `VisionTextExtractor` and would need to move out if the new extractor doesn't provide compatible box coordinates, but they are pure functions of `[TextBox]` with no Vision dependency and can trivially relocate to a shared file.

### Google ML Kit — concrete scope

- Add dependency: `GoogleMLKit/TextRecognition` (~20 MB binary growth on-device; model bundled).
- Adapter layer: replace the `VNRecognizeTextRequest` block in `VisionTextExtractor.extractText` (lines 57–87) with ML Kit's `TextRecognizer.process(VisionImage)` call. ML Kit returns `Text.Block` → `TextLine` → `TextElement` with `frame` bounding boxes — map each `TextElement` onto `TextBox(midX, midY, minX, text)`. The rest of the file — preprocessing, row/column reconstruction, orientation — is untouched.
- Expected delta: ~60 lines of Swift changed in `VisionTextExtractor.swift`, zero changes elsewhere.
- Testing: add 3–5 fixture photos with known-correct extraction, run the adapter, compare output line-by-line.
- Total: **6–10 engineer-hours** for a clean swap, **1 day** including validation on real photos.

### Tesseract — concrete scope

- Dependency: SwiftyTesseract or libtesseract binding.
- Adapter layer: similar shape to the ML Kit swap, but Tesseract doesn't give per-character bounding boxes at the same resolution — the row/column reconstruction quality will be worse out of the box.
- Custom training on the autorefractor font: requires capturing ~500 character samples, training `.traineddata`, validating. 2–3 days.
- Pre-trained numeric quality is generally below ML Kit on receipt-style text.
- Total: **3–5 engineer-days**. Not recommended for the May 1 deadline.

### Hybrid / fallback

- Run Vision first; if `ExtractedText` produces fewer than N valid readings, re-extract with ML Kit.
- Zero behavioral change on the happy path.
- Cost is strictly additive over either engine's cost.
- **~1.5 days** on top of the ML Kit adapter.

---

## 6. Final recommendation

**Do not change OCR code today.** Instrument the field-photo flow instead. Concretely, in this order:

### Phase I — evidence (days 1–2, ≤6 hours of active work)

1. Take 8–10 photos of real autorefractor printouts under realistic lighting (some handheld, some desktop, some partially faded, some at a slight angle). Use the existing app flow — the strict validation will reject most of them and you will get an `OCRDebugSnapshot` per failure.
2. Tap "Show Debug Info" on each failure. Screenshot or export the row-based lines, column-based lines, format detection, and preprocessed JPEG.
3. Categorize each failure against H1–H8 using the table in §3. Write down the distribution.
4. Run **test T1** (visual inspection of preprocessed JPEGs) and **T4** (grep for `AQ` mangling) on the collected snapshots. These cost nothing and decisively narrow the fix.

### Phase II — targeted fix (days 3–5, ~1.5 engineer-days)

Depending on the Phase I result:

- If T1 shows blown-out preprocessed images → apply **A1** (soften preprocessing) and **A2** (dual-pass raw+preprocessed). Re-test against the Phase I snapshots.
- If T4 shows `AQ` mangling → apply **A4** (tolerant quality tail) and **A5** (scoped normalizer).
- Regardless → apply **A3** (relaxed mantissa) as a cheap safety net.

Stop-criterion: >80% of Phase I snapshots now parse ≥3 readings per eye.

### Phase III — parallel safety net (days 3–7, 1–1.5 engineer-days in a branch)

Independently of Phase II, spike the ML Kit swap (**C1**) in a branch. Don't merge — just validate that on the Phase I snapshots it matches or beats Vision. This branch becomes the fallback.

### Phase IV — ship decision (day 7)

- If Phase II hit the stop-criterion: ship Vision with the Tier A fixes. Keep the ML Kit branch dormant.
- If Phase II did not hit the stop-criterion: merge Phase III (either as replacement C1 or fallback C2).

### Why not switch immediately

1. The parser/validator layer was hardened this week (`fbd6b21`); that hardening is correct whether the engine is Vision or ML Kit. Changing the engine now, before observing *what specifically* Vision is doing wrong, means we can't tell whether a subsequent fix worked or whether the problem was in the reconstruction stage (which is engine-agnostic).
2. The committed evidence of Vision-specific failure is limited to **one documented field case** (`111  25  25  -  0.25  54`). That is not enough to justify a 1–2 day swap against a 15-day deadline when a 2-hour preprocessing tweak might do it.
3. The swap cost is genuinely low (one file) and can be held as a safety net in a branch without blocking Phase II.

### Why not fix-and-ship today

1. We don't actually know which hypothesis is dominant. The strict validation fix `fbd6b21` is defensively correct (the old behavior poisoned averages) — the drop rate we're seeing now is the honest-to-goodness Vision miss rate that the old lax parser was papering over with garbage data. Guessing at preprocessing or regex changes without T1 is a 50/50 dart throw.
2. A second fix on top of the strict-validation fix, without evidence, is exactly the anti-pattern in `superpowers:systematic-debugging` Phase 4.5: "3+ fixes failed: question architecture." We are 1 fix in on this symptom and have room to do it right.

### Deadline math

- Deadline: May 1 (15 days from 2026-04-16).
- Phase I: 2 days (active work ≈ 6 hours).
- Phase II: 2 days.
- Phase III (parallel): 3 days wall-clock.
- Buffer for Phase IV decision + shipping + one re-fix: 5 days.
- Remaining: 3 days for Phases 5/6/7/8/9 work or slippage.

The timeline accommodates the evidence-first approach with room to swap engines if needed. It does *not* accommodate a speculative fix that doesn't work, followed by a panicked engine swap in the last week. Evidence first is faster than guessing.

---

## 7. Appendix — instrumentation already in place (do not re-add)

- `AnalysisPlaceholderView.logDebug(...)` — stdout per-photo row-based + column-based dump (lines 314–333 of `AnalysisPlaceholderView.swift`).
- `HandheldFormatParser.parseReadingLine` and `DesktopFormatParser.parseValueTriple` — stdout per-line `Parser: accepted …` / `Parser: rejecting … — reason: shape mismatch | range or token count`.
- `ConsistencyValidator.signMismatch` and `spreadWarning` — stdout average-computation trace.
- `OCRDebugSnapshot` — persisted to CloudKit on any failure; contains both reconstruction strategies, both format detections, parse error, and the preprocessed JPEG.
- `OCRDebugView` — in-session scrollable view with all of the above visible to the operator.

Everything Phase I needs is already shipped. Just take the photos.
