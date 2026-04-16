# HICOR Clinical Research — Light Pass

**Status:** Light pass. Deep pass required before Phase 5 algorithm implementation.
**Date:** 2026-04-16

This document captures a *light pass* (2-3 sources per question, tentative conclusions, no algorithm decisions yet) of the four clinical questions blocking the Phase 5 prescription-averaging algorithm. Each question is flagged for a deep pass before implementation begins.

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

---

> **All four questions are flagged as: "Deep pass required before Phase 5 implementation."** The light-pass conclusions above are working hypotheses to inform the data shapes and service stubs in Phase 1 — they are not authoritative algorithm decisions.
