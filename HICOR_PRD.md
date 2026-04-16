# HICOR – Highlands Church Optical Refraction
## Product Requirements Document (PRD) v1.0
### Prepared for Claude Code Development

---

## 1. Overview

**App Name:** HICOR (Highlands Church Optical Refraction)  
**Platform:** iOS (iPhone first, iPad future)  
**Design Standard:** Apple Liquid Glass / Apple Human Interface Guidelines  
**Bundle ID:** com.creativearchives.hicor (suggested)  
**iCloud Backend:** CloudKit (Public Database — shared across all team devices)  
**Target Launch:** May 1, 2025 (Mexico optical mission trip)

### Mission Context

Highlands Church has conducted optical mission trips to Mexico for over 10 years, providing free eyeglasses to people who cannot afford them. The current refraction workflow involves manual interpretation of autorefractor printouts by individual team members, leading to inconsistency in prescription determination. HICOR standardizes and automates this process using on-device OCR (Apple Vision framework) and evidence-based averaging algorithms, eliminating operator subjectivity.

### Patient Workflow (Context)

1. Patient is registered in FileMaker Pro (external app — not in scope)
2. Patient receives prayer
3. Visual acuity station (20/30 or worse proceeds to refraction)
4. **Refraction station → HICOR is used here**
5. Frame selection
6. Lens grinding
7. Glasses distributed at Sunday service

---

## 2. Core Objectives

- Capture photos of autorefractor printouts (1 photo per slip)
- Extract SPH, CYL, AX, and PD values using on-device OCR
- Apply evidence-based algorithms to determine the best prescription from multiple readings
- Flag inconsistent or unreliable readings and require additional data
- Match the final prescription to available lens inventory
- Display final prescription prominently for manual entry into FileMaker
- Save records to CloudKit for shared team access and historical lookup
- Operate fully offline (except CloudKit sync)

---

## 3. Technology Stack

| Component | Technology |
|---|---|
| Language | Swift |
| UI Framework | SwiftUI |
| OCR / Image Analysis | Apple Vision Framework (on-device, no internet required) |
| Prescription Logic | Native Swift (on-device math/averaging) |
| Database | CloudKit (Public Database) |
| Offline Support | Full offline operation; CloudKit syncs when connectivity available |
| Design | Apple Liquid Glass / Human Interface Guidelines |
| Minimum iOS | iOS 17+ (recommended) |

---

## 4. App Architecture & Screen Flow

```
Launch
  └─► Session Setup Screen (date + location)
        └─► Patient Entry Screen (patient number)
              └─► Photo Capture Screen (1–5 photos)
                    └─► [AI Processing]
                          ├─► Inconsistency Warning/Block → back to Photo Capture
                          └─► Prescription Result Screen
                                └─► Save → History Screen
```

---

## 5. Screen Specifications

### 5.1 Session Setup Screen

Shown at app launch. Remembers last session values and pre-fills them.

**Fields:**
- **Date** — Date picker, defaults to today
- **Location** — Freeform text field (e.g., "San Quintin, Baja California")

**Behavior:**
- Pre-populates with values from last session
- User confirms or edits, then taps "Start Session"
- Values persist in UserDefaults for next launch

---

### 5.2 Patient Entry Screen

**Fields:**
- **Patient Number** — Numeric text field, prominent, large font

**Behavior:**
- User types patient number and taps "Begin Refraction"
- Displays current session date and location at top for confirmation

---

### 5.3 Photo Capture Screen

**Purpose:** Capture photos of autorefractor printout slips (one slip per photo).

**Behavior:**
- Camera opens for each capture
- Supports 2–5 photos per patient
- Each captured photo displays as a thumbnail in a horizontal scroll row
- User can tap "✕" on any thumbnail to remove it
- "Analyze Prescription" button appears once at least 2 photos are captured

**Supported Machine Types:**
- **Desktop autorefractor** — Prints 3 readings per eye + AVG line; includes PD
- **Handheld autorefractor** — Prints 8 readings per eye + machine AVG (`*` line); does **not** include PD

**PD Handling:**
- If PD is not detected in any uploaded photo, display a **prominent red warning banner**:
  > ⚠️ PD not found. Please measure PD manually and enter it below.
- A numeric input field appears for manual PD entry (required before proceeding)
- PD entry is in millimeters (e.g., 63)

---

### 5.4 Prescription Analysis (Processing Logic)

This screen/state handles OCR extraction and prescription calculation. All processing runs on-device using the Apple Vision framework and Swift logic.

#### 5.4.1 OCR Extraction

For each photo:
- Use Apple Vision (`VNRecognizeTextRequest`) to extract all text
- Parse extracted text to identify:
  - `[R]` / `<R>` — Right eye readings
  - `[L]` / `<L>` — Left eye readings
  - SPH, CYL, AX values per reading line
  - AVG / `*` summary line (captured but flagged for research use — see Section 7)
  - PD value (if present)
  - Machine type (inferred from format)

#### 5.4.2 Consistency Validation Rules

**Rule 1 — Plus/Minus Mismatch (SPH sign differs between eyes):**
- If Right eye SPH average is positive and Left eye SPH average is negative (or vice versa):
  - With only 2 printouts: **HARD BLOCK** — user must capture additional reading(s)
  - With 3 or more printouts: **WARNING** — user may override and proceed

**Rule 2 — Reading Spread / Outlier Detection:**
- ⚠️ **Research item for Claude Code:** Investigate and implement the clinically accepted standard method for autorefractor reading consistency thresholds (e.g., acceptable SPH variance across multiple readings). Reference published optometric literature on autorefractor measurement reliability. The algorithm must be consistent and not subject to individual operator judgment.

**Rule 3 — Machine Average Line Usage:**
- ⚠️ **Research item for Claude Code:** Determine whether the machine-calculated AVG / `*` line should be used as an additional data point in the averaging algorithm, or whether HICOR should recalculate from raw readings only. Reference clinical best practices for autorefractor output interpretation.

#### 5.4.3 Prescription Determination Algorithm

- ⚠️ **Research item for Claude Code:** Implement the evidence-based standard for averaging multiple autorefractor readings into a final prescription recommendation. This must produce consistent results regardless of which team member is operating the app. Consider outlier rejection methods (e.g., interquartile range filtering, standard deviation thresholds) as used in clinical optometry.

**Output per eye:**
- SPH (final recommended, rounded to nearest 0.25)
- CYL (final recommended, rounded to nearest 0.25)
- AX (final recommended, rounded to nearest whole degree)

**Output overall:**
- PD (from printout or manual entry)

#### 5.4.4 Lens Inventory Matching

Match the final calculated SPH and CYL for each eye to the closest available lens in inventory.

**Available Inventory (hardcoded for v1):**

SPH range: -6.00 to +6.00 in 0.25 diopter steps (all values, no exceptions)  
No individual gray cell exceptions — every SPH value is available with every available CYL value.

CYL available values: 0.00 (Plano), -0.50, -1.00, -1.50, -2.00 only  
CYL not available: -0.25, -0.75, -1.25, -1.75

AX: not constrained by inventory; use calculated value directly

**Matching Logic:**
- Find the closest available SPH + CYL combination for each eye
- If exact match: use it
- If no exact match: ⚠️ **Research item for Claude Code:** Implement the clinically appropriate rounding/transposition method for matching a calculated prescription to the nearest available lens, considering the full set of readings rather than simple rounding. Present the best match with the delta from the calculated prescription highlighted.
- Display top recommendation per eye; highlight any significant delta

---

### 5.5 Prescription Result Screen

**Purpose:** Display the final prescription clearly for manual transcription into FileMaker.

**Layout (prominent, large text):**

```
─────────────────────────────
         PATIENT #[number]
         [Date] · [Location]
─────────────────────────────
         OD (Right Eye)
  SPH: +1.50   CYL: -0.50   AX: 108
         
         OS (Left Eye)  
  SPH: +1.25   CYL: -0.50   AX: 55

         PD: 59 mm
─────────────────────────────
  Matched Lens — OD: +1.50 / -0.50
  Matched Lens — OS: +1.25 / -0.50
─────────────────────────────
```

**Additional elements:**
- If the matched lens differs from the calculated prescription, show delta in amber
- If consistency warnings were overridden, show a yellow advisory banner
- Photo thumbnails shown below prescription — tappable to full screen with pinch-to-zoom
- "Save Record" button
- "Retake / Add Photo" button (returns to photo capture)

---

### 5.6 History / Lookup Screen

**Default view:** Records entered today, sorted by patient number

**Filters:**
- Date picker to view other days
- Location filter (based on saved session locations)

**List item shows:**
- Patient number
- Date and location
- OD and OS prescription summary (SPH / CYL / AX)
- PD

**Detail view (tap a record):**
- Full prescription display (same layout as Result Screen)
- All captured photo thumbnails — tappable to full screen with pinch-to-zoom
- Raw extracted readings per photo per eye
- Read-only in v1 (editable in future version)

---

## 6. Data Model (CloudKit — Public Database)

### Record Type: `PatientRefraction`

| Field | Type | Notes |
|---|---|---|
| `patientNumber` | String | Required |
| `sessionDate` | Date | Date of session |
| `sessionLocation` | String | Freeform location text |
| `odSPH` | Double | Final right eye SPH |
| `odCYL` | Double | Final right eye CYL |
| `odAX` | Int | Final right eye AX |
| `osSPH` | Double | Final left eye SPH |
| `osCYL` | Double | Final left eye CYL |
| `osAX` | Int | Final left eye AX |
| `pd` | Double | PD in mm |
| `pdManualEntry` | Bool | True if PD was entered manually |
| `matchedLensOD` | String | Matched lens description OD |
| `matchedLensOS` | String | Matched lens description OS |
| `rawReadingsJSON` | String | JSON blob of all extracted readings per photo |
| `photoAssets` | List\<CKAsset\> | Array of captured photos (2–5) |
| `consistencyWarningOverridden` | Bool | True if team overrode a warning |
| `createdAt` | Date | Auto timestamp |
| `deviceID` | String | Device identifier for audit |

### Sync Strategy
- Save locally first (CoreData or SwiftData cache)
- Sync to CloudKit when connectivity available
- Conflict resolution: last-write-wins for v1

---

## 7. Research Items for Claude Code

The following items require clinical research and evidence-based implementation. Claude Code should research published optometric and autorefractor literature before implementing:

1. **Outlier Rejection Threshold:** What SPH/CYL variance across multiple autorefractor readings is clinically considered an outlier? Implement the standard method used in clinical practice.

2. **Machine AVG Line Usage:** Should the machine-calculated average (`*` line on handheld, AVG line on desktop) be included as a data point, or should HICOR recalculate from raw readings only?

3. **Prescription Averaging Algorithm:** What is the evidence-based method for combining multiple autorefractor readings into a single prescription recommendation? (Vector averaging for cylinder/axis may be appropriate.)

4. **Lens Matching Rounding:** What is the clinically appropriate method for rounding/transposing a calculated prescription to the nearest available lens when an exact match is unavailable?

> **Recommended workflow:** Claude Code researches items 1–4, implements the algorithms, then submits the prescription logic module for Codex review before integration.

---

## 8. Consistency & Safety Rules Summary

| Scenario | Action |
|---|---|
| Only 2 printouts, eyes have opposite SPH sign | HARD BLOCK — require more photos |
| 3+ printouts, eyes have opposite SPH sign | WARNING — allow override to proceed |
| Readings spread beyond clinical threshold (TBD by research) | BLOCK — require more photos |
| 4–5 printouts still inconsistent | WARNING — allow override, flag record |
| PD not found in any photo | RED WARNING — require manual PD entry before proceeding |
| Matched lens differs significantly from calculated Rx | AMBER DELTA — highlight difference on result screen |

---

## 9. Lens Inventory (Hardcoded v1)

### Available SPH Values
All values from -6.00 to +6.00 in 0.25 diopter steps (49 values total, including Plano/0.00). No exceptions.

### Available CYL Values
0.00 (Plano), -0.50, -1.00, -1.50, -2.00

**Not available:** -0.25, -0.75, -1.25, -1.75, any value beyond -2.00

### Gray Cell Exceptions
None — every SPH value is available with every available CYL value. No lookup table needed.

---

## 10. Future Versions (Out of Scope for v1)

- Lens inventory import via CSV/PDF upload
- In-app lens inventory editing
- Editable patient records
- iPad optimized layout
- Multi-device real-time sync
- Export / share prescription slip (PDF, AirDrop)
- Integration with FileMaker (direct API)
- Visual acuity recording

---

## 11. Appendix A — Sample Printout Formats

### Desktop Machine (GRK-6000 style)
```
Highlands Optical
VD = 0mm   CYL (-)

<R>    SPH      CYL    AX
     + 1.50   - 0.25   108
     + 1.25   - 1.00   114
     + 1.50   - 0.50   101

AVG  + 1.50   - 0.50   108

<L>    SPH      CYL    AX
     + 1.75   - 0.75    71
     + 1.50   - 0.50    73
     + 0.75   - 0.75    22

AVG  + 1.25   - 0.75    55

PD: 59 mm
```

### Handheld Machine
```
No. 334    VD: 12.0
-REF-

[R]   SPH     CYL    AX
    - 3.25  - 1.00   81 AQ
    - 3.25  - 1.00   80 AQ
    - 3.00  - 2.75   83 AQ
    - 3.50  - 1.75   97 AQ
    - 4.50  - 0.50   71 AQ
    - 3.75  - 0.50   90 AQ
    - 3.25  - 1.00   77 AQ
    - 3.00  - 1.00   83 AQ

  * - 3.25  - 1.00   83   5

[L]   SPH     CYL    AX
    (readings...)

  * +21.00  - 6.25  145   E

(No PD — manual entry required)
```

---

## 12. Non-Functional Requirements

- App must function fully offline (OCR, calculation, local save)
- CloudKit sync occurs automatically when connectivity is restored
- No user login required — uses device identity
- All data stays within Apple's CloudKit infrastructure
- App must be installable via TestFlight for pre-trip testing
- Performance: Photo analysis should complete within 5 seconds per image on iPhone 12 or newer

---

*Document version 1.0 — Created April 2026*  
*For use with Claude Code + Codex review workflow*
