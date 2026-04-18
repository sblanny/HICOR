# GRK-6000 fixture corpus

Real-device captures of GRK-6000 desktop autorefractor printouts, used by
`ROIPipelineFixtureTests` to lock the ROI pipeline against regression.

## Capture protocol

Each photo in this corpus is a real capture from the user's iPhone of an
actual autorefractor slip. Do not invent or synthesize fixture images — the
project policy is that OCR fixtures mirror real machine output.

For each image, add:
1. A JPEG file (`.jpg`) at the appropriate subdirectory.
2. A sibling JSON file with the same stem (`.json`) listing the 24 reading
   values the physical slip shows.

Example: `dim_good_framing/case-001.jpg` + `dim_good_framing/case-001.json`.

## Subdirectories

- `dim_good_framing/` — refraction-room lighting, printout well-centered.
- `dim_tilted/` — refraction-room lighting, printout rotated 10-20 degrees.
- `bright_good_framing/` — well-lit baseline for sanity.
- `dim_poor_framing/` — printout off-center or partially cropped. Expected to
  fail with `incompleteCells` error.

## Expected JSON schema

```json
{
  "expected": {
    "right": {
      "r1":  { "sph": "-1.25", "cyl": "-0.50", "ax": "108" },
      "r2":  { "sph": "-1.25", "cyl": "-0.50", "ax": "105" },
      "r3":  { "sph": "-1.50", "cyl": "-0.50", "ax": "110" },
      "avg": { "sph": "-1.25", "cyl": "-0.50", "ax": "108" }
    },
    "left": {
      "r1":  { "sph": "-2.25", "cyl": "-0.75", "ax":  "92" },
      "r2":  { "sph": "-2.50", "cyl": "-0.50", "ax":  "90" },
      "r3":  { "sph": "-2.50", "cyl": "-0.75", "ax":  "88" },
      "avg": { "sph": "-2.50", "cyl": "-0.75", "ax":  "90" }
    }
  },
  "shouldFail": false
}
```

For `dim_poor_framing/` entries, set `shouldFail: true` and omit the
`expected` block (the test asserts `incompleteCells` is thrown).

## Adding new fixtures

1. Capture on the iPhone using the in-app CaptureView (torch as the
   clinician would use it).
2. Air-drop / Files-app export the captured JPEG onto this Mac.
3. Read the physical slip and transcribe all 24 readings into the JSON.
4. Commit image + JSON together.
