# HICOR Training Guide — Mission Volunteer Manual

Welcome! This guide explains how to use HICOR at the refraction station during the mission trip.

## What HICOR Does

HICOR helps you turn an autorefractor printout into a final eyeglass prescription. Instead of reading the printout by hand and guessing which numbers to use, you take a photo of the printout and HICOR figures out the prescription for you. This way every patient gets the same kind of careful analysis, no matter who is at the station.

## Setting Up at the Start of the Day

1. Open HICOR.
2. Confirm or change today's **date** (it usually fills in automatically).
3. Type the **location** (e.g., "San Quintin"). The app remembers your last entry.
4. Tap **Start Session**.

You only need to do this once per day.

## Entering a Patient

1. Look at the patient's registration card from FileMaker.
2. Type the **patient number** in the big field.
3. Tap **Begin Refraction**.

## Photographing a Printout

1. Place each printout slip on a flat, well-lit surface.
2. Make sure all numbers and the entire slip fit in the camera view.
3. **Take 2 printouts minimum.** Every patient is scanned on the autorefractor 2–5 times. Photograph each printout.
4. If a photo looks blurry or cut off, tap the **✕** on its thumbnail and retake it.
5. When all your photos look good, tap **Analyze Prescription**.

> **If the app prompts for another photo**, the readings from the printouts you captured don't agree well enough to trust. Take another printout on the autorefractor and add it. If after **5 printouts** the readings still don't agree, **consult the team leader** — don't override.

**Tips for a good photo:**
- Hold the phone parallel to the printout — don't tilt.
- Avoid shadows from your hand or head.
- Indoor lighting is fine; direct sunlight may overexpose.

## What the Warnings Mean

### "Readings don't agree — add another printout"

The photos you captured disagree on this patient's prescription. Take another printout on the autorefractor and photograph it. HICOR keeps your existing photos; just add one more.

### "Consult team leader"

You've captured 5 printouts and the readings still disagree. Stop and get the team leader — don't try to average noise into a prescription.

### Red "reading excluded" banner on the results screen

HICOR dropped one reading from the average because the other printouts agreed and that one didn't. The banner shows which eye, which photo, and why. The final prescription is calculated from the remaining readings. This is informational — no action needed unless the exclusion looks wrong to you, in which case raise it with the team leader.

### Red PD Banner

> "PD not found. Please measure PD manually and enter it below."

This appears when none of your photos contain a PD value (this is normal for handheld machines). **Measure the PD with a ruler or PD ruler card** and type the millimeter value (e.g., 63) into the field. Then continue.

## Reading the Result Screen

```
PATIENT #042
April 16, 2026 · San Quintin

OD (Right Eye)
SPH: +1.50   CYL: -0.50   AX: 108

OS (Left Eye)
SPH: +1.25   CYL: -0.50   AX: 55

PD: 59 mm

Matched Lens — OD: +1.50 / -0.50
Matched Lens — OS: +1.25 / -0.50
```

- **OD = Right eye** (oculus dexter)
- **OS = Left eye** (oculus sinister)
- **SPH** = sphere power (the main correction)
- **CYL** = cylinder (correction for astigmatism)
- **AX** = axis (where the cylinder sits, in degrees)
- **PD** = pupillary distance (between the centers of your pupils)
- **Matched Lens** = the actual lens we have in inventory that's closest to the prescription

If the matched lens differs from the calculated prescription, the difference is shown in **amber**. That's normal — we don't carry every possible lens.

Write the **Matched Lens** values into FileMaker for the lens-grinding station.

Tap **Save Record** when done.

## Looking Up a Previous Patient

1. Open the **History** screen from the menu.
2. Today's records appear first, sorted by patient number.
3. To see a different day, tap the date filter.
4. Tap any record to see the full prescription and original photos.

## Offline Use

HICOR works **without internet**. You can take photos, analyze, and save records anywhere. When the device reconnects to WiFi (e.g., back at the church or hotel), records sync automatically to the team's shared CloudKit database.

You don't have to do anything special for sync to happen. Just keep the app installed and open it once you're back on WiFi.

## Who to Contact

If something doesn't look right or the app crashes, tell **[Team Lead Name]** right away. **Don't proceed if you're unsure** — getting the prescription wrong means the patient gets glasses that don't help.
