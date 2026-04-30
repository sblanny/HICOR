# MIKE_RX_PROCEDURE.md
## Clinical Algorithm for HICOR Prescription Computation
**Last updated:** April 28, 2026 (escalation threshold matched to implementation: Manual Review fires at 5 printouts, not 4)
**Status:** Authoritative — this document is the source of truth for Phase 5 implementation

---

## Purpose

HICOR encodes Mike Claudio's 10 years of mission-trip clinical judgment into an algorithm a volunteer can execute reliably. Volunteers who do this 2-3 times per year cannot replicate Mike's experience-based intuition. This document specifies the rules that let the app make the call Mike would make.

**Scope for v1 (May 1, 2026 trip):** The app takes 2-5 photos of autorefractor printouts, performs OCR, computes a final prescription, and **displays it on screen**. The volunteer reads the displayed values and types them into FileMaker. HICOR's role ends at the display. No lens matching, no inventory tracking, no dispensing logic within HICOR.

---

## Notation Key

Mike uses optician-standard centidiopter notation in his written answers:
- `+100` = +1.00 D
- `-300` = -3.00 D
- `+800` = +8.00 D

HICOR code and this document use decimal diopter values (e.g., 1.00, -3.00).

---

## Core Principles

### 1. Two-printout minimum, five-printout maximum
Every patient gets minimum 2 printouts from the autorefractor. Up to 5 if consistency issues arise. Cross-printout validation is the clinical safety gate — one printout alone is never sufficient for dispensing.

### 2. Operator transparency
HICOR never hides clinical decisions from the operator. Dropped outliers, excluded readings, and tier assignments are always surfaced on screen — never silent.

### 3. When Mike and industry standards differ
Mike's clinical thresholds take precedence (field experience beats theoretical precision). Industry standards are used for mathematical correctness (axis circularity, power-vector decomposition) where Mike approximates with mental arithmetic.

### 4. Refer-out is a routine outcome
Mike estimates 10-25% of patients will be referred out. UI tone must treat this as informative, not alarming.

---

## Algorithm Sections

### Section 1: SPH and CYL Agreement Thresholds

**Two readings "agree" when:**
- SPH values within **1.00 D** of each other (Mike's clinical threshold, matches industry repeatability)
- CYL values within **0.50 D** of each other (industry standard for autorefractor CYL repeatability)

**When readings disagree:**
- 2 printouts disagreeing on SPH or CYL → require 3rd printout
- 3 printouts still disagreeing → require 4th
- 4 printouts still disagreeing → require 5th
- 5 printouts with fewer than 2 agreeing → **escalate to Manual Review Required**

### Section 2: AXIS Agreement — Sliding Scale by CYL Magnitude

Axis tolerance scales inversely with cylinder power (industry practice, loosely aligned with ANSI Z80.1-2005 dispensing tolerances):

| CYL magnitude | Axis agreement tolerance |
|---------------|--------------------------|
| 0 to -0.25 D | 30° |
| -0.25 to -0.50 D | 20° |
| -0.50 to -1.00 D | 15° |
| -1.00 to -2.00 D | 10° |
| Below -2.00 D | 7° |

**For averaging axis across multiple readings:** use Thibos J0/J45 power-vector decomposition (axis is circular; simple arithmetic averaging is mathematically wrong).

### Section 3: Clinical Gates Requiring Minimum 3 Readings

Even when 2 printouts are internally consistent, the following situations require a minimum of 3 readings before computing a final prescription:

- (a) One eye plus sign, other eye minus sign (antimetropia)
- (b) R/L SPH difference > 3.00 D
- (c) One eye near plano (±1.00 D) and other eye over ±5.00 D
- (d) R or L SPH over ±10.00 D

**Antimetropia is stricter:** ANY mixed-sign case requires **minimum 4 printouts** (not 3) so outliers can be discarded while preserving enough data for confident computation.

### Section 4: Machine AVG Line — Trust with Validation

The autorefractor prints individual readings plus an AVG line. Mike trusts the AVG by default.

**HICOR rule:**
1. Default to machine AVG as the prescription source
2. Validate: independently compute Thibos M (spherical equivalent) from raw readings using power-vector math
3. If |machineAVG_M − computed_M| ≤ 0.50 D → use machine AVG (Mike's preference)
4. If disagreement > 0.50 D → outlier likely present. Apply MAD-based outlier rejection on raw readings, recompute, ignore machine AVG
5. Mike's CYL caveat: if computed CYL > -1.00 D (more cylinder magnitude), prefer the higher (more negative) SPH reading

### Section 5: Outlier Rejection and Manual Review Escalation

**Need minimum 2 printouts agreeing to trust a result.**

- 2 printouts agreeing → trust, proceed
- 2 printouts disagreeing → take a 3rd
- 3 printouts with 2 agreeing and 1 outlier → trust the 2 agreeing readings, surface the outlier on screen
- 3 printouts all disagreeing → take a 4th
- 4 printouts still disagreeing → take a 5th
- 5 printouts with fewer than 2 agreeing → **Manual Review Required**

**Manual Review Required flow:**
- App displays all OCR readouts in a clear table on screen
- Banner: "Manual Review Required — Consult Mike or Scott"
- Mike or Scott examines the screen alongside the physical printouts
- They decide the prescription manually and enter it directly into FileMaker
- HICOR records this as a manual-review outcome

### Section 6: Final Value Rounding

Lenses are available in 0.25 D steps. Final computed values must be rounded to dispensable values.

**SPH rounding rule (Mike, April 20):**
- If |CYL| > 1.00 D → round SPH to **stronger correction** (more magnitude)
  - Example: -2.37 → -2.50, +2.37 → +2.50
- If |CYL| ≤ 1.00 D → round SPH to **weaker correction** (less magnitude)
  - Example: -2.37 → -2.25, +2.37 → +2.25

**Rationale:** When cylinder is significant, additional spherical magnitude compensates for the cylinder's effect on overall vision. When cylinder is low, under-correcting slightly is more comfortable and avoids over-correction eye strain.

**CYL rounding (Mike, April 26):**
- Round to nearest 0.50 D step (matches Highlands Optical inventory; lenses are NOT stocked in 0.25 D CYL increments)
- For values exactly between two 0.50 steps (e.g., -1.75): direction depends on the eye's own SPH magnitude
  - |SPH| < 3.00 D → round CYL **weaker** (toward zero)
  - |SPH| ≥ 3.00 D → round CYL **stronger** (away from zero)
- Each eye decides its own CYL rounding based on its own SPH magnitude (per-eye rule, not whole-prescription)

**Rationale:** When SPH is significant (≥3.00 D), the eye needs substantial total correction; rounding CYL stronger gives adequate astigmatism correction. When SPH is low, over-correcting astigmatism on a mild prescription causes discomfort.

**Examples:**
- SPH -2.50, computed CYL -1.75 → |SPH| 2.50 < 3.00 → weaker → CYL -1.50
- SPH -3.00, computed CYL -1.75 → |SPH| 3.00 ≥ 3.00 → stronger → CYL -2.00
- SPH -5.00, computed CYL -2.25 → |SPH| 5.00 ≥ 3.00 → stronger → CYL -2.50
- SPH -1.50, computed CYL -2.75 → |SPH| 1.50 < 3.00 → weaker → CYL -2.50

**AX rounding:** round to nearest integer degree (1° precision is industry standard).

### Section 7: Dispensing Tier System

Five tiers determine whether and how to display the prescription:

#### Tier 0 — No Glasses Needed (with symptom check)
**Trigger:** BOTH eyes have |SPH| ≤ 0.25 AND |CYL| ≤ 0.50

**Display:** Ask the patient three symptom questions:
- "Do you have trouble seeing the board at school or work?"
- "Do you have trouble driving at night?"
- "Do you have any other vision problems we should know about?"

**Two actions:**
- "No symptoms — no glasses needed" → records "no glasses dispensed, no symptoms"
- "Yes, has symptoms — show prescription" → display the prescription; operator uses judgment

**Asymmetric case:** If only ONE eye qualifies for Tier 0, still dispense glasses (plano lens for the low eye). Tier 0 only triggers when BOTH eyes qualify.

#### Tier 1 — Normal Range
**Trigger:** SPH within ±6.00 D, CYL magnitude ≤ 2.00 D

**Display:** Final prescription, no special banner. Proceed normally.

#### Tier 2 — Stretch Range (Patient Notification Required)
**Trigger:** SPH between ±6.00 and ±8.00 D, OR CYL magnitude between 2.00 and 3.00 D

**Display:** Final prescription with banner:
> "Patient notification required: This prescription is at the edge of our available lens range. Inform the patient their glasses may not fully correct their vision."

Operator confirms "Patient has been notified" before proceeding.

#### Tier 3 — Do Not Dispense (Hard Ceiling)
**Trigger:** SPH beyond ±8.00 D, OR CYL magnitude beyond 3.00 D

**Display:** Banner:
> "Prescription exceeds dispensable range. Do not issue glasses. Refer to professional care."

**No operator override.** ±8.00 D is a hard clinical ceiling per Mike (April 20).

#### Tier 4 — Medical Concern
**Trigger:** SPH beyond ±12.00 D

**Display:** Banner:
> "Medical concern: Prescription over ±12.00 D may indicate cataracts or other eye conditions requiring professional evaluation. Do not dispense. Refer to medical care."

Record as a medical referral for trip documentation.

### Section 8: Anisometropia (R/L Difference)

**Same-sign anisometropia:**
- |R_SPH − L_SPH| ≤ 2.00 D → dispense normally
- |R_SPH − L_SPH| > 2.00 D → flag advisory: "Anisometropia detected. May cause depth perception issues. Patient notification required."
- |R_SPH − L_SPH| > 3.00 D → take 3 readings, look for <3 D option, otherwise refer out

**Mixed-sign anisometropia (antimetropia):**
- Both eyes within −1.50 to +1.50 D → dispense (treat as low-power separate prescriptions)
- Either eye outside ±1.50 D → refer out (do not dispense)
- ANY mixed-sign case → require minimum 4 printouts
- When dispensing mixed-sign: each eye receives its own SPH from its own readings. The lowest absolute SPH value is surfaced to the operator as an awareness flag (`antimetropiaDispense(lowestAbsEye:)`) so they can confirm the patient understands the unusual prescription. Do NOT apply one eye's SPH to both eyes — that would under/over-correct one eye and break binocular fusion. (Mike clarification, April 28, 2026.)

### Section 9: PD (Pupillary Distance) Aggregation

**Mike's rule:**
1. Extract PD from each printout where present
2. If only 1 PD available → use it
3. If multiple PD values → compute mean
4. If max(PD) − min(PD) > 5 mm → flag: "PD readings vary significantly. Please measure manually."
5. Display computed PD with source annotation ("averaged from 3 printouts" or "manually entered")

### Section 10: SPH-Only Readings

Autorefractor sometimes prints SPH without CYL/AX values (when CYL is undetectable or too low to measure).

**Rule:**
- Readings with isSphOnly == true contribute to SPH averaging
- Their placeholder CYL=0, AX=0 do NOT contribute to CYL/AX averaging
- If all readings for an eye are SPH-only → final prescription has CYL=0, AX=0, flag SPHOnlyReadings

---

## Phase 5 Algorithm Priority Order

When the ConsistencyValidator returns `.consistent`, PrescriptionCalculator processes in this order:

1. **Sign determination** (with clinical gates a-d triggering minimum 3 readings)
2. **Cross-printout aggregation** via Thibos M/J0/J45 power vectors
3. **Machine AVG validation** (compare to computed, prefer AVG if within 0.50 D)
4. **Outlier detection** (MAD-based + 1.00 D SPH / 0.50 D CYL / sliding-scale axis)
5. **Final value computation** (CYL-dependent SPH rounding per Section 6)
6. **Anisometropia check** (Section 8)
7. **Tier assignment** (Tier 0 through Tier 4 per Section 7)
8. **PD aggregation** (Section 9)
9. **Clinical flags collection** for UI display

---

## Implementation Constants

```swift
// Cross-printout agreement thresholds
static let sphAgreementThreshold: Double = 1.00   // Mike's clinical threshold
static let cylAgreementThreshold: Double = 0.50   // Industry standard

// Axis agreement — sliding scale by CYL magnitude
static let axisToleranceCylUnder025: Double = 30.0
static let axisToleranceCyl025To050: Double = 20.0
static let axisToleranceCyl050To100: Double = 15.0
static let axisToleranceCyl100To200: Double = 10.0
static let axisToleranceCylOver200: Double = 7.0

// Machine AVG validation tolerance
static let machineAvgValidationThreshold: Double = 0.50

// Anisometropia thresholds
static let anisometropiaAdvisoryThreshold: Double = 2.00
static let anisometropiaReferOutThreshold: Double = 3.00
static let antimetropiaBothEyesMaxAbs: Double = 1.50
static let antimetropiaMinimumPrintouts: Int = 4

// Clinical gates requiring 3+ readings
static let rlDiffTriggersMin3: Double = 3.00
static let onePlanoOtherHighTrigger: Double = 5.00
static let highSphTrigger: Double = 10.00

// Tier 0 (no glasses needed) thresholds
static let tier0SphMax: Double = 0.25
static let tier0CylMax: Double = 0.50  // absolute value

// Tier boundaries
static let sphTier1Max: Double = 6.00        // Tier 1 upper bound
static let sphTier2Max: Double = 8.00        // Tier 2 upper bound (HARD CEILING)
static let sphMedicalConcernMin: Double = 12.00  // Tier 4 threshold
static let cylTier1Max: Double = 2.00        // Tier 1 upper bound (absolute)
static let cylTier2Max: Double = 3.00        // Tier 2 upper bound (absolute)

// Rounding
static let cylBreakpointForSphRounding: Double = 1.00  // |CYL| > 1.00 rounds up
static let cylRoundingStep: Double = 0.50              // CYL inventory is 0.50 D steps
static let sphMagnitudeThresholdForCylRounding: Double = 3.00  // tie direction

// PD aggregation
static let pdMaxSpreadBeforeManual: Double = 5.0  // mm

// Manual review escalation: ConsistencyValidator returns
// `.inconsistentEscalate` when the printout count reaches
// `Constants.maxPrintoutsAllowed` (5) without 2+ printouts agreeing.
```

---

## Test Fixtures Required for Phase 5

Build test cases from these scenarios:

**Sign and agreement:**
- 2 printouts agreeing within 0.50 D → consistent, use AVG
- 2 printouts differing by 1.50 D → require 3rd
- 3 printouts: -2.00, -2.25, -4.50 with AVG -2.25 → trust AVG (Mike's example)
- 5 printouts all disagreeing → Manual Review Required

**Axis:**
- CYL -0.25, axis 10° vs 35° → 25° difference, within 30° tolerance → consistent
- CYL -1.50, axis 10° vs 22° → 12° difference, exceeds 10° tolerance → flag

**Tier assignment:**
- Both eyes SPH +0.00, CYL 0.00 → Tier 0 with symptom check
- R SPH +0.25 CYL -0.25, L SPH -2.50 → asymmetric, dispense (plano for R)
- SPH -5.50 → Tier 1 normal
- SPH -7.50 → Tier 2 stretch with notification
- SPH -9.00 → Tier 3 refer out
- SPH -13.00 → Tier 4 medical concern

**Anisometropia:**
- R -2.00, L -4.00 → 2D same sign → normal
- R -2.00, L -5.00 → 3D same sign → advisory
- R +1.00, L -1.00 → antimetropia, both within ±1.50 → dispense with 4 printouts
- R +2.00, L -1.00 → antimetropia, one outside ±1.50 → refer out

**Rounding (SPH):**
- Computed -2.37 with CYL -0.50 → CYL ≤ 1.00, round to weaker → -2.25
- Computed -2.37 with CYL -1.50 → CYL > 1.00, round to stronger → -2.50
- Computed +2.37 with CYL -0.50 → +2.25
- Computed +2.37 with CYL -1.50 → +2.50

**Rounding (CYL — 0.50 D step, SPH-driven tie direction):**
- Computed CYL -1.30, SPH -2.00 → clear nearest 0.50 step → -1.50
- Computed CYL -1.85, SPH -2.00 → clear nearest 0.50 step → -2.00
- Computed CYL -1.75, SPH -2.50 → tie, |SPH| 2.50 < 3.00, weaker → -1.50
- Computed CYL -1.75, SPH -3.00 → tie, |SPH| 3.00 ≥ 3.00, stronger → -2.00
- Computed CYL -2.25, SPH -5.00 → tie, |SPH| 5.00 ≥ 3.00, stronger → -2.50
- Computed CYL -1.25, SPH -0.50 → tie, |SPH| 0.50 < 3.00, weaker → -1.00
- Computed CYL -2.75, SPH -1.50 → tie, |SPH| 1.50 < 3.00, weaker → -2.50
- Computed CYL 0.00 (any SPH) → 0.00 (plano stays plano)

**PD:**
- PDs 62, 64, 65 → mean 63.67, rounded 64, flag: none
- PDs 60, 64, 68 → spread 8mm → flag for manual measurement

**SPH-only:**
- All 3 readings SPH-only → final prescription CYL=0, AX=0, flag SPHOnlyReadings

---

## Document History

- **April 17, 2026** — Initial procedure document from Mike Claudio
- **April 19, 2026** — Mike's inventory tier clarification via text (±6/±8/±12 tiers)
- **April 19, 2026** — Mike's detailed Q&A response (SPH threshold, axis, anisometropia, PD)
- **April 20, 2026** — Live Q&A session finalizing:
  - CYL agreement threshold (0.50 D per industry)
  - Axis sliding scale (industry-leaning)
  - Tier 0 (no-glasses) with symptom check
  - Asymmetric Tier 0 → dispense with plano
  - Antimetropia 4-printout rule, ±1.50 boundary, use lowest absolute
  - ±8.00 D hard ceiling (no override)
  - Rounding rule: CYL-dependent up/down
  - Manual Review Required escalation path (display OCR, consult Mike/Scott)
  - Scope clarification: HICOR ends at prescription display, FileMaker handles dispensing
- **April 26, 2026** — CYL rounding rule corrected: Highlands Optical inventory does not stock 0.25 D CYL increments, so CYL rounds to nearest 0.50 D step. Tie direction is per-eye, driven by that eye's SPH magnitude (|SPH| ≥ 3.00 → stronger; otherwise weaker).
- **April 28, 2026** — Escalation threshold updated to match implementation. `ConsistencyValidator` fires `.inconsistentEscalate` at `Constants.maxPrintoutsAllowed` (5), not 4. Document was previously stale on this. Behavior unchanged; doc now matches code. See `AUDIT_2026-04-27.md`.
- **April 28, 2026** — Mike clarification on antimetropia SPH application: each eye uses its own SPH from its own readings; the "lowest absolute SPH" is operator awareness, not a calculation override. Resolves audit Issue D.
