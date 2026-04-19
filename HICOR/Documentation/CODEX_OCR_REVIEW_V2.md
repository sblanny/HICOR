# HICOR OCR Independent Review V2 (ROI Pipeline)

Date: 2026-04-18  
Reviewer: Codex (independent pass)

## Bottom line first

The ROI pipeline is a meaningful upgrade over the old "full image text dump + parser rescue" approach, and the safety posture (fail closed on incomplete extraction) is the right default for clinical risk. The current 95.1% per-cell result looks close to the practical ML Kit ceiling on this input class without larger model or workflow changes.

The bigger pre-trip risk is not "silent wrong numbers" anymore; it is operational friction from re-capture loops once you leave the narrow `dim_good_framing` condition.

Given 13 days left and Phases 5-9 still pending, OCR should move to stabilization mode, not feature mode.

---

## 1) Quick wins (<1 day each, ranked by ROI)

1. **Run a focused fixture expansion pass (highest ROI, lowest risk).**  
   Fill `dim_tilted`, `bright_good_framing`, and `dim_poor_framing` with at least 5 real captures each using the existing `FixtureCaptureView` workflow. This gives immediate signal on field behavior and catches overfitting to the current 6-image corpus.

2. **Add a pre-capture guidance overlay line in `CaptureView`.**  
   Explicitly instruct: "Torch on, fill frame, hold steady." This is likely a bigger real-world lift than another parser heuristic tweak.

3. **Log structured failure reasons from `incompleteCells` by class, not just labels.**  
   Distinguish anchor failure, sign-missing, shape-mismatch, and empty-cell cases in debug snapshots. This makes remaining misses triageable in hours instead of guesswork.

4. **Add one "retry once with same image" path before user recapture prompt.**  
   On `incompleteCells`, rerun with `ImageEnhancer.aggressive` end-to-end once. Cheap to implement, no UI complexity, and may recover borderline dim captures.

5. **Add a narrow sign-recovery heuristic for isolated SPH sign drops only.**  
   You already do section sign propagation; add explicit test coverage for plus-eye cases so this does not drift toward "default negative." This is a precision hardening step, not a broad accuracy jump.

6. **Do not spend a day on dropped-leading-digit reconstruction heuristics yet.**  
   For many cases (`.75` vs `1.75`, `25` vs `1.25`) inference is ambiguous without stronger priors. Cheap heuristics here can create silent wrong values, which is worse than re-capture.

### On the 7 remaining misses

- **Dropped leading digits:** mostly near ML Kit recognition limits on thermal glyph quality; some are irrecoverable post-OCR without risky inference.
- **Absent signs:** partially mitigated already (adjacent sign pick + section propagation + AVG hint), but still vulnerable when both local sign token and reliable section baseline are missing.
- **Glyph misreads:** partially fixable with normalization (`A->4`, `C->0`, comma/period), but remaining cases are mostly recognizer-level.

Verdict: there are small wins left, but no credible <1-day change likely turns 95.1% into "near-perfect" across varied field conditions.

---

## 2) Risks for the trip (what can still go wrong on May 1)

1. **Re-capture loops in non-ideal capture conditions.**  
   Only `dim_good_framing` has real fixtures today (6 captures). Off-angle, glare, blur, or partial-frame scenarios are unmeasured in this branch.

2. **All-or-nothing gate amplifies per-cell miss rate into per-photo failures.**  
   At 95.1% per-cell, full 24-cell success can still be operationally low in tougher conditions. Safety is protected, but throughput risk is real.

3. **Runtime fallback is effectively disabled for successful extraction.**  
   `ROIPipelineExtractor.fallbackOrThrow` invokes fallback extraction but then always throws `incompleteCells`, forcing recapture. This is not a true runtime "fallback succeeds" path.

4. **Clinical source-of-truth doc is missing from this checkout.**  
   `MIKE_RX_PROCEDURE.md` could not be found in repo. That blocks strict compliance verification and increases risk of subtle interpretation drift.

5. **High-value edge ranges are underrepresented in ROI fixtures.**  
   Current ROI image fixtures span SPH about `-5.25..+1.25`; high hyperopia / extreme values are not represented in the live ROI corpus.

6. **Field-debug complexity is non-trivial.**  
   The pipeline now has multiple heuristics (header-gap split, 30% X-slop, merged-token split/merge, sign conventions). Diagnosing novel failures onsite requires disciplined logs and rollback readiness.

---

## 3) Capture conditions to test before deployment

Prioritize these in this exact order:

1. **Dim + tilted (10-25 deg)** with torch both on and off.
2. **Bright overhead glare** (hotspots crossing SPH/CYL headers and row values).
3. **Slight motion blur** (single-handed capture in clinic pace).
4. **Partial framing errors** (top clipped, bottom clipped, left/right cropped).
5. **Curled/crinkled thermal paper** (non-planar slip causes local warping).
6. **Faded/smudged printouts** (low contrast, broken glyphs).
7. **Shadow/occlusion** (finger shadow, pen tip near one column).
8. **Distance variation** (printout occupies 45%, 60%, 75% of frame).
9. **Plus-prescription and high-SPH examples** (to stress sign logic and leading digit retention).
10. **Asymmetric eyes and extreme AX (near 1 and 180)** in same batch.

Minimum target before May 1: **30 additional real captures** across these buckets, with at least 5 each for the first four.

---

## 4) Architectural assessment: ROI pipeline vs simple MLKitTextExtractor

## ROI pipeline (`ROIPipelineExtractor`)

Best when:
- You need clinical safety over convenience (reject incomplete reads).
- Layout is fixed (GRK-6000 desktop) and anchor math is reliable.
- You can enforce capture discipline (framing + torch).

Strengths:
- Strong defense against silent wrong values.
- Domain-specific constraints encoded where they belong.
- Better than parser-only rescue from full-image OCR noise.

Costs:
- Higher maintenance and debugging burden (many heuristic layers).
- More moving parts to regress under unseen capture conditions.
- "Fallback" currently behaves as recapture escalation, not alternate successful extraction.

## Simple extractor (`MLKitTextExtractor`)

Best when:
- You need broad tolerance and fast iteration with lower complexity.
- You accept more parser ambiguity and post-filtering.

Strengths:
- Simpler stack, easier to reason about.
- Fewer calibration parameters.

Costs:
- More vulnerable to cross-column token fusion and context confusion.
- Higher chance of partial garbage that parser must reject.

## Rollback viability

Rollback to simple extractor remains viable and quick at app level (default extractor swap in `OCRService`), but note:
- Current ROI fallback path is not a "successful fallback extraction" path.
- If field issues appear, rollback is viable as a build/release decision, not as automatic runtime rescue inside the current ROI extractor.

Recommendation: do a rollback drill now (one dry-run branch flip + fixture run) so this is operationally proven, not theoretical.

---

## 5) All-or-nothing gate calibration

For this mission context, the gate is **safety-correct**: better to force recapture than pass uncertain values.

However, it is **operationally strict** and likely to create re-capture loops outside ideal framing/lighting unless capture discipline is enforced and fixture coverage broadens immediately.

Recommended calibration stance for May 1:
- Keep all-or-nothing policy.
- Add one automatic internal retry with aggressive enhancement before surfacing recapture.
- Improve capture guidance and operator training.
- Keep a non-app manual fallback workflow ready for persistent fails.

So: not "too strict clinically," but currently under-supported operationally.

---

## 6) Edge-case handling assessment

- **Unusual high SPH / extreme values:** parser plausibility ranges allow them, but ROI image corpus does not yet validate them sufficiently.
- **Asymmetric eyes:** structurally supported.
- **Missing AVG line:** ROI path usually fails closed earlier (missing cells -> recapture), which is safe. Desktop parser also has a negative default sign hint if AVG absent; this is a potential bias risk if ever reached.
- **Smudged/faded thermal:** likely to trigger `incompleteCells` and recapture, not silent wrong values (good fail mode).
- **Merged/split fragments:** several targeted repairs already exist and are well chosen (`X.XX-Y.YY` splitter, overlap merge, dotless reshape).

Overall: failure mode is mostly "reject and retry," which is appropriate for v1.

---

## 7) Mike procedure compliance and Phase 5 data shape

Full compliance cannot be conclusively certified from this checkout because `MIKE_RX_PROCEDURE.md` is missing.

What is true in code now:
- Extraction emits per-eye structured readings plus machine AVG values (`EyeReading.machineAvgSPH/CYL/AX`).
- SPH sign handling reflects the stated intent (local sign, section propagation, AVG hinting).
- `RawReading.isSphOnly` is preserved for downstream averaging filters.

This data shape is appropriate for Phase 5 averaging inputs, provided Phase 5 honors:
- SPH-only rows contribute to SPH only.
- Placeholder CYL/AX for SPH-only rows are excluded from vector/cylinder averaging.

Action item: restore/verify `MIKE_RX_PROCEDURE.md` in repo and add direct mapping tests from procedure examples to parsed structures.

---

## 8) Ship / no-ship recommendation for May 1

**Recommendation: Ship with current OCR architecture, with strict pre-trip validation gates.**

Why ship:
- Silent-wrong-risk is significantly reduced.
- Pipeline is already integrated and testable.
- Deadline pressure is now dominated by Phases 5-9.

Ship conditions (must meet in next few days):
1. Add real fixtures in at least the top four capture-condition buckets.
2. Confirm acceptable retry burden in field-like capture runs.
3. Perform rollback drill to `MLKitTextExtractor` so contingency is proven.
4. Confirm `MIKE_RX_PROCEDURE.md` presence and Phase 5 contract alignment.

If those conditions fail, ship risk becomes operational (workflow stall), not primarily algorithmic.

---

## 9) Time allocation recommendation (remaining 13 days)

Recommended split:
- **OCR refinement/stabilization: 20%**
- **Phase 5-9 implementation and integration: 80%**

Reasoning:
- OCR has crossed the threshold where additional effort has diminishing returns unless you expand real-world capture coverage first.
- The larger delivery risk is unfinished downstream workflow (averaging, lens matching, results UX, release hardening), not the current OCR core.

Suggested OCR budget use:
- 60% of OCR time on capture-condition validation corpus expansion.
- 25% on instrumentation + one-retry hardening.
- 15% on rollback drill + operational playbook.

Do not start major OCR architecture changes before May 1 unless field testing reveals a true blocking failure mode.
