# Mike Claudio's Rx Printout Reading Procedure
## Clinical Algorithm Reference — Source of Truth for Phase 5

**Author:** Mike Claudio — founder of the Highlands Church optical clinics, 10+ years of field experience
**Date captured:** April 17, 2026
**Use:** This document is the authoritative clinical algorithm for HICOR's prescription determination logic. Phase 5 implementation must follow this procedure.

---

## How to Read an Rx Printout from the Refractor

**Rx = Prescription**

Reading left to right across a printout row:
- **R** = Right Eye
- **SPH** = Sphere — the power of the lens
- **CYL** (Cylinder) = amount of astigmatism correction
- **AXIS** = location of the CYL on a graph of 0 to 180 degrees (1 degree increments)

---

## Procedure (Gilras Table Top Unit — Desktop Format)

### Data collection
1. Start with right eye. You will obtain 3 results.
2. Switch to left eye. You will obtain 3 results.

### Sign determination (plus vs minus)
3. Confirm if the prescription is a **+/Plus** or **-/Minus** prescription.
4. At least **2 out of 3 readings** will determine if + or minus.
5. If any one of the readings is **drastically different** from the others, do not take that reading into consideration.

### Sign mismatch handling
6. If one eye is plus and the other is minus, **repeat the procedure several times**.
7. If the readings still show one eye plus and one eye minus, **consult the Optical team leader**.

### Final prescription calculation
8. If **both eyes are minus (SPH)**, use the **calculated average on the 4th line** of readings (the AVG line).
9. Use the available lens parameters to compare and calculate the final prescription.
10. If **both eyes are plus (SPH)**, use the **calculated printed prescription on the 4th line** of readings.
11. Use the available lens parameters to compare and calculate the final prescription.
12. When determining the final readings, **remember the available SPH lens powers and the available cylinder/astigmatism limits**.

### Axis
13. **The AXIS determines the location of the CYLINDER/astigmatism.**

### Inventory limits
14. There are times you will give the highest possible parameters but must inform the patient that the prescription will not be as strong as it should be.
15. **If the prescription printed is over +800 or -800** (i.e., outside ±6.00 diopter inventory): consider **not providing eyewear** because the top parameter of +600 or -600 will not correct vision adequately.
16. **If the cylinder is over -300** (i.e., stronger than -2.00): consider **not providing eyewear** because the top parameter for cylinder is -200 and will not correct adequately.

---

## Key Clinical Insights Captured from Mike

### 1. Outlier rejection is simpler than the research suggested
Mike's rule: "If any one of the readings is drastically different from the others, do not take that reading into consideration."

**Translation for algorithm:** Use a simple outlier rejection — compute the median of the 3 readings, drop any reading that differs substantially from the median. No complex power-vector decomposition required for outlier detection. The clinician's mental model is "2 out of 3 agree, the 3rd is thrown out."

### 2. The machine AVG line IS trusted — but only for same-sign cases
Mike's rules 8 and 10 explicitly direct the operator to "go to the calculated average on the 4th line" — that's the AVG line on the desktop printout.

**Translation for algorithm:**
- When both eyes have same-sign SPH: **use the machine AVG line as the starting point**
- When signs differ: the AVG line is not trusted and the operator should retake readings or escalate

### 3. Sign consistency is the #1 clinical quality check
Mike dedicates rules 3-7 entirely to sign determination. This is the most important validation.

**Translation for algorithm:** The ConsistencyValidator's sign-mismatch rule is core to Mike's procedure — it's not a defensive programming check, it's a primary clinical gate.

### 4. "Drastic" is the operator's judgment call
Mike doesn't define an exact threshold for "drastically different." The current 0.50 D spread threshold in HICOR is a reasonable approximation but Mike's process is more qualitative than quantitative.

**Translation for algorithm:** A strict numeric threshold may be wrong. Consider showing the operator all 3 readings and letting them override any outlier rejection the algorithm performs. The operator's judgment is preserved.

### 5. Inventory limits are a hard cap
Mike's rules 15 and 16 are clinical: if the refraction is too strong for available lenses, **don't dispense glasses**. This is a patient-safety decision, not a software limitation.

**Translation for algorithm:** When SPH is outside ±6.00 or CYL is beyond -2.00, HICOR must explicitly flag "prescription exceeds available lens inventory" with guidance that the patient may not benefit from the available glasses. Do not silently clamp to nearest available.

---

## User Clarifications (April 17, 2026)

### On using all readings, not just the AVG line
"We need all of the lines. The average could be flawed because some lines should be thrown out and not used. So the average line maybe should be tossed out in some cases, but in others it's really the gold standard."

**Translation for algorithm:**
- Do NOT blindly trust the machine AVG line
- Validate raw readings first — check for consistency and outliers
- If raw readings are consistent → trust the AVG line (it matches)
- If outliers are detected → recompute average from non-outlier readings, ignore AVG line
- Show operator both machine AVG and computed average if they differ

### On desktop vs handheld usage
"We use the desktop more than the handheld."

**Translation for v1 scope:** Desktop format (GRK-6000) is the primary instrument. Handheld support is deferred to post-trip.

---

## Phase 5 input shape

Phase 5 consumes `[PrintoutResult]` (2–5 elements per patient). Each element carries per-eye `EyeReading` values: a list of `RawReading` rows plus the machine-printed AVG/`*` line (`machineAvgSPH/CYL/AX`, and for handheld `handheldStarConfidence*`). Aggregate all `RawReading` values across photos per eye for Thibos M/J0/J45 vector averaging with MAD outlier rejection (see `RESEARCH.md`). The machine AVG lines are additional data points with their own confidence weighting per `RESEARCH.md` Q3 — cross-checked against the computed average, not a blind replacement.

`ConsistencyValidator` runs before Phase 5 and has already:
- blocked any cross-eye or per-eye sign mismatch (returning `.inconsistentAddPhoto` or `.inconsistentEscalate`)
- blocked any per-eye SPH/CYL spread > 0.75 D across the full printout set
- stripped clear single-photo outliers when 3+ photos were captured (surfaced via `Result.consistent(droppedOutliers:)`)

So Phase 5 can assume it receives a mutually consistent `[PrintoutResult]`. The `droppedOutliers` list travels alongside the results for display in `PrescriptionAnalysisView`; Phase 5 does not re-introduce those readings.

## How This Maps to HICOR Phase 5 Implementation

### Averaging algorithm
- Take all 3 readings per eye
- Determine sign by majority (2 of 3)
- Drop the outlier (the one "drastically different" from the majority)
- Use the remaining 2 or use the machine AVG line if signs agree AND no outliers detected

### Consistency validation
- If SPH signs differ between eyes → warn the operator (Mike's rule 6-7)
- With multiple captures, if signs still differ → escalate to team leader (not a hard stop, an advisory)

### Lens matching
- Match calculated SPH to nearest available in ±0.25 D steps within ±6.00 range
- Match calculated CYL to nearest of [0, -0.50, -1.00, -1.50, -2.00]
- If required CYL exceeds -2.00 → flag patient as unsuitable for available inventory
- If required SPH exceeds ±6.00 → flag patient as unsuitable for available inventory

### UI requirement (derived from Mike)
- Show the operator the 3 original readings AND the computed final prescription
- Allow the operator to override any single reading being marked as "outlier"
- Allow manual override of final prescription values with reason captured in the record

---

## Handheld format addendum

Mike's guide focuses on the 3-reading Gilras desktop format. The handheld format (8 readings per eye) is used as a secondary when the desktop can't get a clean reading. The same principles apply:
- Majority rules for sign
- Drop outliers
- Machine AVG line is on the `*` row, includes a confidence number 1-9

For handheld with 8 readings, the outlier rejection has more data to work with and should be more statistically robust — but the clinical gate (sign consistency, inventory limits) remains identical.

**Note:** Handheld support is deferred to post-trip Phase 10. Do not implement handheld algorithm for v1.

---

## Open Questions for Mike (if available before Phase 5)

1. What is the definition of "drastically different"? A specific diopter threshold, or purely qualitative?
2. When do you choose desktop vs handheld? First-line desktop, fallback handheld?
3. For handheld's 8 readings, do you still use a similar 2-of-3 majority rule, or is there a different approach?
4. What's your actual rejection rate — how often do patients have Rx outside inventory?
5. Is there a separate procedure for patients with very different Rx between eyes (anisometropia)?
