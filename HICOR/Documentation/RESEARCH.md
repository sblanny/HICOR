# HICOR Clinical Research

**Status:** Deep pass complete. Final algorithmic decisions captured below each question. Phase 5 implements directly from these decisions.
**Light pass date:** 2026-04-16
**Deep pass date:** 2026-04-16

This document captures both the original *light pass* (tentative conclusions per question) and the subsequent *deep pass* (final algorithmic decisions, marked **✅ Final Decision** under each question). The deep-pass decisions are the authoritative spec — Phase 5 implements directly from them.

---

## Q1: Averaging Multiple Autorefractor Readings

**Tentative conclusion:** Use **power-vector decomposition** (Thibos M / J0 / J45) to average sphere–cylinder pairs. Arithmetic averaging of cylinder and axis directly is mathematically incorrect for oblique axes (axis values wrap at 180°, so averaging 5° and 175° naively gives 90° instead of the correct ~0°). The Thibos transformation converts each (SPH, CYL, AX) into three orthogonal scalar components (M = spherical equivalent, J0 = horizontal/vertical cross-cylinder, J45 = oblique cross-cylinder), which can be averaged arithmetically and then converted back to (SPH, CYL, AX).

**Sources (light pass):**
1. Thibos LN, Wheeler W, Horner D. *Power vectors: an application of Fourier analysis to the description and statistical analysis of refractive error.* Optom Vis Sci. 1997. — [PubMed 9255814](https://pubmed.ncbi.nlm.nih.gov/9255814/)
2. *Power vector analysis of the optical outcome of refractive surgery* — [PubMed 11165859](https://pubmed.ncbi.nlm.nih.gov/11165859/)
3. *Refractive Focus* — Contact Lens Spectrum, August 2014 — [clspectrum.com](https://clspectrum.com/issues/2014/august/refractive-focus/)

**Open questions for deep pass:**
- Should readings be weighted (e.g., by reliability indicator) or treated equally?
- How to handle the back-conversion when J0/J45 round-trip produces a tiny CYL near zero (potential AX instability)?
- What rounding strategy on the final SPH/CYL/AX preserves clinical equivalence (see Q4)?

### ✅ Final Decision (Q1)

**Algorithm: Equal-weighted Thibos M/J0/J45 averaging with safe back-conversion.**

**Forward conversion (per individual reading) — `(SPH, CYL, AX) → (M, J0, J45)`:**

```
M   = SPH + 0.5 · CYL
J0  = -0.5 · CYL · cos(2 · AX_rad)
J45 = -0.5 · CYL · sin(2 · AX_rad)
```

where `AX_rad = AX × π / 180`. CYL is in minus-cylinder convention (negative). Source: Thibos LN, Wheeler W, Horner D, *Optom Vis Sci* 1997 ([PubMed 9255814](https://pubmed.ncbi.nlm.nih.gov/9255814/)); formula reproduction in *Dioptric power and refractive behaviour* ([PMC 8977790](https://pmc.ncbi.nlm.nih.gov/articles/PMC8977790/)).

**Average across all qualifying readings (post-Q2 outlier rejection):**

```
M_avg   = mean(M_i)
J0_avg  = mean(J0_i)
J45_avg = mean(J45_i)
```

Equal weighting. The literature does not establish a quantitatively superior weighting scheme for the field-clinic context (mix of desktop + handheld + machine AVG), and equal-weighting is robust and defensible.

**Back-conversion — `(M, J0, J45) → (SPH, CYL, AX)`:**

```
J_magnitude = sqrt(J0² + J45²)
CYL  = -2 · J_magnitude                    // always ≤ 0 (minus-cyl convention)
SPH  = M - 0.5 · CYL = M + J_magnitude     // since CYL is negative
AX   = 0.5 · atan2(J45, J0) · 180/π        // degrees, then normalize to (0, 180]
```

Axis normalization: if the result is ≤ 0, add 180; if > 180, subtract 180. Standard convention treats AX = 0 as AX = 180.

**Edge cases:**

1. **Plano cylinder collapse.** If `J_magnitude < 0.125` D, force `CYL = 0`, `SPH = round(M, 0.25)`, `AX = 0` (omit axis for plano-only Rx). This avoids AX instability when the average is essentially spherical — a small numeric perturbation in J0/J45 must not produce a clinically meaningful axis.

2. **Final precision.** Round `SPH` to nearest 0.25 D and `CYL` to nearest 0.25 D (raw clinical Rx precision). Round `AX` to the nearest 5° increment (well within ANSI Z80.1 ±7° axis tolerance for 0.50 D cyl — see Q4).

3. **Sign of CYL after rounding.** If rounding leaves CYL = 0 but SPH was computed assuming CYL ≠ 0, recompute `SPH = round(M, 0.25)` from the spherical equivalent directly. Prevents a 0.125 D drift between the two paths.

**Worked example.** Three desktop readings, right eye:

| # | SPH | CYL | AX | M | J0 | J45 |
|---|-----|-----|-----|------|-------|-------|
| 1 | +1.50 | -0.50 | 108° | +1.25 | -0.222 | +0.149 |
| 2 | +1.50 | -0.25 | 105° | +1.375 | -0.116 | +0.063 |
| 3 | +1.75 | -0.50 | 110° | +1.50 | -0.230 | +0.144 |

Means: M_avg = +1.375, J0_avg = -0.189, J45_avg = +0.119. J_magnitude = 0.223. CYL = -0.446 → round -0.50. SPH = 1.375 + 0.223 = 1.598 → round +1.50. AX = 0.5·atan2(0.119, -0.189)·180/π = 0.5·148° = 74° → round to 75°. **Result: +1.50 / -0.50 × 75°.**

---

## Q2: Outlier Rejection Threshold

**Tentative conclusion:** Clinical repeatability of modern autorefractors is generally tighter than ±0.50 D for sphere and ±0.37 D for cylinder, with cycloplegic 95% limits of agreement around ±0.32 D. A practical outlier threshold for Phase 1's purposes is **a per-component deviation > 0.50 D from the median of the readings** — this matches the ANSI Z80.1 spectacle tolerance band and the "no clinical relevance" threshold cited across multiple repeatability studies. For astigmatic components evaluated as power vectors, J0 and J45 coefficients of repeatability of <0.29 D and <0.38 D respectively are reasonable rejection bands.

**Sources (light pass):**
1. *Does the Accuracy and Repeatability of Refractive Error Estimates Depend on the Measurement Principle of Autorefractors?* — [PMC 7794271](https://pmc.ncbi.nlm.nih.gov/articles/PMC7794271/)
2. *Repeatability (test–retest variability) of refractive error measurement in clinical settings* — [ResearchGate](https://www.researchgate.net/publication/6906263_Repeatability_test-retest_variability_of_refractive_error_measurement_in_clinical_settings)
3. *Autorefractors* — StatPearls / NCBI — [NBK580520](https://www.ncbi.nlm.nih.gov/books/NBK580520/)

**Open questions for deep pass:**
- IQR vs. SD vs. absolute-D threshold — which gives the most stable behaviour with only 2-5 readings?
- Whether to reject in (SPH, CYL, AX) space or in (M, J0, J45) space (probably the latter, since J0/J45 are independent and have known repeatability bands).
- How to handle the case where rejection drops the sample below the minimum (re-prompt for more photos vs. proceed with what's left).

### ✅ Final Decision (Q2)

**Algorithm: Component-wise Median Absolute Deviation (MAD) rejection in power-vector space, with a hard ANSI-Z80.1 fallback floor.**

**Why MAD over SD/IQR.** Sample sizes are small (3-5 readings on desktop, 8 on handheld, plus optional AVG/* line ≈ N=4-9 per eye). The sample standard deviation is a poor estimator at small N when extreme outliers are present, which is exactly the failure mode here (one OCR misread or one machine misalignment). MAD is robust by construction — a single bad reading cannot inflate the dispersion estimate. Sources: [Median absolute deviation (Wikipedia)](https://en.wikipedia.org/wiki/Median_absolute_deviation); *Multiple Desirable Methods in Outlier Detection of Univariate Data* ([PMC 8801745](https://pmc.ncbi.nlm.nih.gov/articles/PMC8801745/)); *Data science: Use MAD instead of z-score* ([hausetutorials](https://hausetutorials.netlify.app/posts/2019-10-07-outlier-detection-with-median-absolute-deviation/)).

**Why power-vector space.** J0 and J45 are independent; raw CYL and AX are not (axis wraps at 180°). Rejecting on (SPH, CYL, AX) directly produces nonsense at oblique axes. M, J0, J45 are scalar and additive — component-wise rejection is mathematically valid. Repeatability bands from *Effect of six different autorefractor designs* ([PMC 9704684](https://pmc.ncbi.nlm.nih.gov/articles/PMC9704684/)): Sw ≤ 0.55 D for M, ≤ 0.35 D for J0/J45.

**Procedure.** For each eye, after Q1 forward-conversion of all raw readings to (M, J0, J45):

```
For each component C in {M, J0, J45}:
    median_C = median(C_i across all readings)
    MAD_C    = median(|C_i - median_C|)
    MAD_C    = max(MAD_C, 0.05)   // floor: prevents rejecting identical readings
    threshold_C = 3.0 · MAD_C     // k=3 (conservative; preserves N at small sample sizes)

reject reading i if  ANY of:
    |M_i   - median_M|   > threshold_M
    |J0_i  - median_J0|  > threshold_J0
    |J45_i - median_J45| > threshold_J45
```

**k = 3 selection.** Standard MAD outlier thresholds in the literature use k = 2, 2.5, or 3 (Miller 1991, cited in MAD methodology references). HICOR uses k = 3 because the sample is small and clinically marginal readings should be retained, not aggressively trimmed. Combined with the MAD floor of 0.05 D, this yields rejection only on genuinely large deviations (≥ 0.15 D minimum).

**Hard ANSI safety net.** Independent of MAD, also reject any reading whose M differs from `median_M` by **more than 1.00 D** (exceeds two ANSI Z80.1 sphere tolerances and clear OCR/misalignment territory). This guards against the case where MAD itself is inflated by a heavily skewed sample.

**Sample-size floor and fallback.** If outlier rejection would leave `< 3 readings` for an eye:
1. Discard the rejection — keep all original readings.
2. Set `consistencyResult = .warningOverridable` with message *"Readings vary widely for this eye. Check the printout and consider retaking."*
3. Compute the average from the un-trimmed pool (so the user sees a real number, not an error).

**Spread threshold (used by ConsistencyValidator at the UI layer).** Independent of per-reading rejection: if `max(M_i) - min(M_i) > 0.75 D` or `max(J_magnitude_i) - min(J_magnitude_i) > 0.50 D` *after* outlier rejection, set `consistencyResult = .warningOverridable`. These thresholds are 1.5× the autorefractor within-subject Sw (a "noisy but plausibly real" band) and inform the user without blocking flow.

**Edge case: AX wrap.** Never compute `max(AX) - min(AX)` directly — wraps at 180°. Spread is measured on J0/J45 (which already encode axis correctly).

**Worked example.** Five right-eye M values: {1.25, 1.375, 1.50, 1.50, 4.75}. Median = 1.50. Deviations: {0.25, 0.125, 0, 0, 3.25}. MAD = 0.125. Threshold = 3 × 0.125 = 0.375. Reading at 4.75 is rejected (deviation 3.25 ≫ 0.375). Also caught by the 1.00 D hard ANSI safety net. Remaining N = 4 ≥ 3, so rejection stands. Surviving median = 1.4375.

---

## Q3: Machine AVG / `*` Line Inclusion

**Tentative conclusion:** The machine's own AVG (or `*`) line is computed by the manufacturer's proprietary outlier filter and is generally reliable for desktop units in clinical agreement studies (within 0.50 D of subjective refraction in ~87% of eyes). For HICOR, the safest light-pass position is to **include the machine AVG as one additional reading in the pool, weighted equally**, rather than treating it as the canonical answer or excluding it entirely. Handheld units sometimes lack a true AVG line (using a `*` or reliability indicator instead); for those, the per-line readings are the only input. A deep pass should decide whether to *replace* the per-line readings with the AVG when both are available, or treat them as independent samples.

**Sources (light pass):**
1. *Design and Clinical Evaluation of a Handheld Wavefront Autorefractor* — [PubMed 26580271](https://pubmed.ncbi.nlm.nih.gov/26580271/)
2. *Clinical Evaluation of an Affordable Handheld Wavefront Autorefractor in an Adult Population in a Low-Resource Setting in the Amazonas* — [MDPI Vision 9/4/94](https://www.mdpi.com/2411-5150/9/4/94)
3. *Refractive outcomes of table-mounted and hand-held auto-refractometers in children* — [BMC Ophthalmology](https://bmcophthalmol.biomedcentral.com/articles/10.1186/s12886-021-02199-5)

**Open questions for deep pass:**
- Treat machine AVG as a separate "secondary" data point with reduced weight, or as a peer reading?
- Whether the `*` reliability indicator on handheld units should *gate* inclusion of that reading rather than just annotate it.
- Confirm behaviour when a printout shows an AVG line whose values fall outside the per-line range (suggests manufacturer post-processing the user can't see).

### ✅ Final Decision (Q3)

**Algorithm: Include both AVG (desktop) and `*` (handheld) lines as peer readings, gated on confidence-or-quality flags. Same equal-weight Q1 averaging applies.**

**Desktop AVG line.**

- Treat the desktop AVG line as **one peer reading** in the pool, indistinguishable from per-line readings during Q1 averaging and Q2 outlier rejection.
- Rationale: the manufacturer's averaging algorithm is closed-source but generally agrees with subjective refraction within 0.50 D in ~87% of eyes (per *Accuracy of Autorefraction in Children* — [AAO](https://www.aaojournal.org/article/S0161-6420(20)30231-1/fulltext); table-mounted comparison study — [BMC Ophthalmol](https://bmcophthalmol.biomedcentral.com/articles/10.1186/s12886-021-02199-5)). Including it as a peer (not a replacement, not a weighted favorite) lets it pull the pool toward the manufacturer's view without overriding genuine variability the per-line readings reveal.
- If MAD-based rejection in Q2 trims the AVG line, that's fine — the per-line readings already disagree with it strongly enough that it should not influence the result.

**Handheld `*` line with confidence score (1-9).**

- The `*` line carries a trailing confidence digit. Per Retinomax study ([PubMed 17435531](https://pubmed.ncbi.nlm.nih.gov/17435531/)), manufacturer recommends ≥ 8 for reliable single-measurement screening, but specificity drops sharply below that threshold.
- HICOR is **not** doing single-measurement screening — it is pooling multiple readings. A mediocre `*` line is dampened by the rest of the pool, so the `≥ 8` threshold is overly strict.
- **Inclusion rule:** include the handheld `*` line as a peer reading **if confidence ≥ 5** (mid-scale); skip entirely if confidence < 5. Below 5 the indicator says the machine itself does not trust its own average, and inclusion would import noise.
- If `*` confidence is missing from the parse, default to **including** (do not punish OCR ambiguity by dropping a likely-valid reading).

**E-quality (low-confidence) per-line readings on handheld.**

- Readings ending in `E` get `lowConfidence = true` on `RawReading` (Phase 4 model change).
- **Do not auto-drop** them in Q1 — include in the pool, let MAD rejection (Q2) catch them if they're genuine outliers.
- After averaging, if `> 50%` of the contributing readings for an eye were `lowConfidence`, set `consistencyResult = .warningOverridable` with message *"Most readings for this eye were marked low quality by the machine. Verify before dispensing."* This is informational; user can override.

**AVG/* falling outside the per-line range.**

- Do nothing special at the parse stage. The MAD rejection in Q2 will detect this (AVG outside the per-line range will deviate strongly from the median). If MAD trims it, fine. If MAD keeps it (because per-line readings themselves are spread), the user sees the wide spread via the Q2 spread-threshold warning.

**Out-of-scope (deferred to a future revision):**

- Per-reading confidence weighting (vs. equal weight) — no clear evidence base for the field-clinic mix; revisit if real-world data shows systematic bias.
- Handheld `*` confidence used as a *weight* rather than a binary gate — same reason.

---

## Q4: Lens Matching Rounding

**Tentative conclusion:** ANSI Z80.1-2015 specifies fabrication tolerances of ±0.13 D for sphere (within ±6.50 D), ±0.13 D for cylinder (above -2.00 D), and ±7° axis for 0.50 D cylinders / ±14° for 0.25 D cylinders. For inventory matching, the pragmatic approach is to **preserve spherical equivalent** (SE = SPH + CYL/2) when snapping to the nearest available lens, rather than rounding SPH and CYL independently — this minimizes the dioptric error felt by the patient. The HICOR inventory uses 0.25 D SPH steps and a fixed CYL set of {0, -0.50, -1.00, -1.50, -2.00}, which is well within ANSI tolerance bands but coarser than typical Rx precision; the matcher will need to choose the closest CYL bucket *first*, then optimize SPH to preserve SE.

**Sources (light pass):**
1. *ANSI Z80.1-2015 Quick Reference Guide* — The Vision Council — [thevisioncouncil.org](https://thevisioncouncil.org/sites/default/files/ANSI%20Z80%201-2015_Quick%20Reference%20v2.pdf)
2. *Honing Spectacle Lens Verification Expertise* — 20/20 Magazine — [2020mag.com](https://www.2020mag.com/article/honing-spectacle-lens-verification-expertise)
3. *OptiCampus ANSI Z80.1-2010 Summary* — Optivision — [opticampus.opti.vision](https://opticampus.opti.vision/tools/ansi.php)

**Open questions for deep pass:**
- Preserve spherical equivalent vs. preserve sphere — which produces better real-world acuity for the inventory we carry?
- Cylinder transposition rules: when a calculated Rx has CYL between two inventory buckets, should we round the CYL and re-compute the SPH offset, or pick whichever bucket minimises total power-vector distance in (M, J0, J45) space?
- Axis rounding: inventory has no axis dependence (all CYL options are stocked in any axis ground at the lab), but the tolerance window may still inform whether to recommend rounding the final AX to 5° or 1° increments.

### ✅ Final Decision (Q4)

**Algorithm: Spherical-equivalent-preserving snap. For each candidate inventory CYL bucket, derive the SPH that preserves the calculated SE; pick the bucket with the smallest residual.**

**Reference tolerances** ([ANSI Z80.1 via OptiCampus](https://opticampus.opti.vision/tools/ansi.php)):

| Parameter | Range | Tolerance |
|---|---|---|
| Sphere | 0 to ±6.50 D | ±0.13 D |
| Cylinder | ≤ 2.00 D | ±0.13 D |
| Axis | 0.25 D cyl | ±14° |
| Axis | 0.50 D cyl | ±7° |
| Axis | 0.75 D cyl | ±5° |
| Axis | 1.00–1.50 D cyl | ±3° |
| Axis | > 1.50 D cyl | ±2° |

These tolerances apply to **lens fabrication** (dispensed lens vs. its label). They are not the relevant metric for inventory matching, which is "what stocked lens gives best vision compared to the calculated Rx." The clinically meaningful metric there is **dioptric distance in power-vector space**, dominated by spherical equivalent at small angular offsets.

**Procedure.** Given calculated `(SPH_calc, CYL_calc, AX_calc)` from Q1 and inventory `CYL_set = {0, -0.50, -1.00, -1.50, -2.00}` and `SPH_step = 0.25 D`:

```
SE_target = SPH_calc + 0.5 · CYL_calc

best = nil
for each CYL_b in CYL_set:
    SPH_b_raw   = SE_target - 0.5 · CYL_b
    SPH_b       = round(SPH_b_raw, 0.25)   // snap to inventory SPH grid
    SE_actual   = SPH_b + 0.5 · CYL_b
    SE_residual = abs(SE_actual - SE_target)
    cyl_distance = abs(CYL_calc - CYL_b)
    score = SE_residual + 0.10 · cyl_distance   // weak tiebreak toward closer CYL
    if best == nil or score < best.score:
        best = (SPH_b, CYL_b, SE_residual, cyl_distance, score)
```

**Tie-break weight `0.10`.** SE preservation dominates (this is what the patient feels). The `0.10 · cyl_distance` term breaks ties between two CYL buckets with identical SE residual, favoring the bucket closer to the calculated CYL — this reduces astigmatic mis-correction when SE is achievable equally well by either bucket.

**Axis handling.**

- HICOR inventory is single-vision, axis-independent (lab grinds CYL to any axis on order).
- Preserve `AX_calc` from Q1 directly. Round to nearest **5° increment** for clinical practicality and dispenser legibility (well within the ±7° ANSI tolerance for the 0.50 D cyl band, which is HICOR's most common cyl).
- If selected `CYL_b == 0` (plano cyl), set `AX_dispensed = 0` (omit) — axis is meaningless without cylinder.

**Out-of-range flagging.**

- If `cyl_distance > 0.50 D` for the best match (e.g., calculated CYL = -2.50 vs. nearest inventory -2.00), set `outsideInventoryRange = true` on the result and surface a warning in the dispensing screen: *"Calculated cylinder exceeds inventory range. Best available match shown — verify acceptable."*
- If `SE_residual > 0.25 D` for the best match, set `outsideInventoryRange = true` and warn similarly. (Should not occur under normal calculated Rx — would imply both SPH and CYL are dramatically off-grid.)

**Worked example 1 — clean fit.** Calculated `+1.50 / -0.50 × 75°`. SE = +1.25.

| CYL_b | SPH_b_raw | SPH_b | SE_actual | residual |
|---|---|---|---|---|
| 0 | +1.25 | +1.25 | +1.25 | 0.00 ✓ |
| -0.50 | +1.50 | +1.50 | +1.25 | 0.00 ✓ |
| -1.00 | +1.75 | +1.75 | +1.25 | 0.00 ✓ |
| -1.50 | +2.00 | +2.00 | +1.25 | 0.00 ✓ |
| -2.00 | +2.25 | +2.25 | +1.25 | 0.00 ✓ |

All five tie on SE residual. Tiebreak: `cyl_distance` minimum at CYL_b = -0.50 (distance 0). **Result: +1.50 / -0.50 × 75°.**

**Worked example 2 — between buckets.** Calculated `-2.30 / -0.75 × 90°`. SE = -2.675.

| CYL_b | SPH_b_raw | SPH_b | SE_actual | residual |
|---|---|---|---|---|
| -0.50 | -2.425 | -2.50 | -2.75 | 0.075 |
| -1.00 | -2.175 | -2.25 | -2.75 | 0.075 |

Tied SE residual. Cyl_distance: -0.50 → 0.25, -1.00 → 0.25 — also tied. Final tiebreak: lower-magnitude CYL preferred (closer to plano = better tolerated patient-side). **Result: -2.50 / -0.50 × 90°.**

---

## Summary table

| # | Decision | Phase 5 implementation pointer |
|---|---|---|
| 1 | Equal-weight M/J0/J45 average; safe back-conversion with plano collapse | `PrescriptionAverager.average(_:)` |
| 2 | k=3 component-wise MAD in (M, J0, J45) space + 1.00 D hard ANSI floor + N≥3 fallback | `OutlierFilter.reject(_:)` |
| 3 | Include AVG/* as peer readings; handheld `*` gated on confidence ≥ 5 | `OutlierFilter.assemblePool(_:)` |
| 4 | SE-preserving snap with `0.10 · cyl_distance` tiebreak, AX rounded to 5° | `LensMatcher.match(_:)` |

> **All four questions resolved.** Phase 4 needs only the structural artifacts these decisions imply (the `lowConfidence` field on `RawReading`, the `ConsistencyValidator` spread/sign rules using the Q2 thresholds). Phase 5 implements the algorithms above directly from this document.
