# ROI Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an ROI-based OCR pipeline for the GRK-6000 desktop autorefractor printout that reaches ≥95% reading accuracy on dim refraction-room captures, with all-or-nothing extraction that surfaces a re-capture prompt rather than partial results.

**Architecture:** A new `ROIPipelineExtractor` conforms to the existing `TextExtracting` protocol, so no downstream code changes. It composes seven new components, built bottom-up: `ImageEnhancer` + `DocumentRectifier` (preprocessing leaves) → `Anchors`/`CellLayout`/`CellROIExtractor` (geometry leaves) → `AnchorDetector` + `CellOCR` (ML Kit consumers) → `ROIPipelineExtractor` (orchestrator). A new `CaptureView` replaces `CameraPickerView` to add torch and a framing guide. `MLKitTextExtractor` stays in the codebase as an explicit fallback for captures the ROI pipeline can't handle.

**Tech Stack:** Swift 5.10, SwiftUI, UIKit, AVFoundation, Vision, Core Image, Google ML Kit Text Recognition v2 (already vendored via CocoaPods), XCTest. Target iOS 17+, iPhone only.

**Branch:** Work continues on `feat/mlkit-text-extraction`. Do not branch again. Commit after every passing step.

---

## Build and test commands

Run these from the repo root (`/Users/scott/Projects/HICOR`):

- Regenerate Xcode project after adding/removing files: `xcodegen generate && pod install`
  - **IMPORTANT:** `pod install` is not optional. `xcodegen generate` overwrites `HICOR.xcodeproj`, wiping out the CocoaPods xcconfig integration. Without a follow-up `pod install`, every subsequent build fails with `Unable to find module dependency: 'MLKitTextRecognition'`. Always chain the two. `pod install` with an unchanged Podfile.lock finishes in ~2 seconds.
- Build (no signing, simulator target): `xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Run all tests on simulator: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO`
- Run one test class: append `-only-testing:HICORTests/<TestClassName>` to the test command (e.g., `-only-testing:HICORTests/ImageEnhancerTests`)

If `iPhone 16 Pro` isn't installed locally, run `xcrun simctl list devices available` and pick any iOS 17+ simulator.

---

## File map

**New production files** (all under `HICOR/`):

| Path | Responsibility |
|------|----------------|
| `HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift` | Pure Core Image pipeline — contrast/gamma/unsharp. Two strengths. |
| `HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift` | Detect printout rectangle with Vision, perspective-warp to long-side-horizontal UIImage. |
| `HICOR/Services/OCR/ROI/Anchors.swift` | Data types only — `SectionAnchors`, `Anchors`, `CellROI` enums/struct. |
| `HICOR/Services/OCR/ROI/CellLayout.swift` | Pure function: `Anchors` → 24 `CellROI` rectangles for GRK-6000 grid. |
| `HICOR/Services/OCR/ROI/CellROIExtractor.swift` | Pure function: crop `[CellROI]` from a `UIImage` with padding. |
| `HICOR/Services/OCR/ROI/LineRecognizing.swift` | `LineRecognizing` protocol + `MLKitLineRecognizer` wrapper. Enables injection for tests. |
| `HICOR/Services/OCR/ROI/AnchorDetector.swift` | Consumes `LineRecognizing`, returns `Anchors` or throws `insufficientAnchors`. |
| `HICOR/Services/OCR/ROI/CellOCR.swift` | Consumes `LineRecognizing`, reads one cell with shape validation and one retry on aggressive enhancement. |
| `HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift` | Orchestrator. Conforms to `TextExtracting`. All-or-nothing gate. Fallback delegation. |
| `HICOR/Views/CaptureView.swift` | AVFoundation-based capture view with torch toggle and framing overlay. |

**New test files** (all under `HICORTests/`):

| Path | Covers |
|------|--------|
| `HICORTests/OCR/Preprocessing/ImageEnhancerTests.swift` | Contrast/gamma effect on a synthetic gray image. |
| `HICORTests/OCR/Preprocessing/DocumentRectifierTests.swift` | Rectangle selection, orientation normalization, nil on no-rectangle. |
| `HICORTests/OCR/ROI/CellLayoutTests.swift` | 24-cell grid math from hand-built `Anchors`. |
| `HICORTests/OCR/ROI/CellROIExtractorTests.swift` | Crop dimensions, padding. |
| `HICORTests/OCR/ROI/AnchorDetectorTests.swift` | Anchor grouping, quorum throw, section assignment. |
| `HICORTests/OCR/ROI/CellOCRTests.swift` | Shape validation, retry behavior, nil on double-fail. |
| `HICORTests/OCR/ROI/ROIPipelineExtractorTests.swift` | Happy path, rectify-nil fallback, anchor-throw fallback, incomplete-cells error. |
| `HICORTests/OCR/ROI/ROIPipelineFixtureTests.swift` | Layer 2 — real captured fixture images + expected JSON. |

**Modified files:**

| Path | Change |
|------|--------|
| `HICOR/Services/OCR/OCRService.swift` | Add `OCRError.incompleteCells(missing: [String])` case. Default extractor becomes `ROIPipelineExtractor(fallback: MLKitTextExtractor())`. |
| `HICOR/Views/AnalysisPlaceholderView.swift` | Extend `humanReadable(_ error:)` for `.incompleteCells`. |
| `HICOR/Views/PhotoCaptureView.swift` | Swap `CameraPickerView` for `CaptureView`. |

**Deleted files:**

| Path | Reason |
|------|--------|
| `HICOR/Views/CameraPickerView.swift` | Replaced by `CaptureView`. |

**Fixture corpus** (created in Task 14):

| Path | Purpose |
|------|---------|
| `HICORTests/OCR/Fixtures/Images/grk6000/dim_good_framing/*.{jpg,json}` | Dim + well-framed captures. |
| `HICORTests/OCR/Fixtures/Images/grk6000/dim_tilted/*.{jpg,json}` | Dim + 10–20° printout tilt. |
| `HICORTests/OCR/Fixtures/Images/grk6000/bright_good_framing/*.{jpg,json}` | Baseline sanity. |
| `HICORTests/OCR/Fixtures/Images/grk6000/dim_poor_framing/*.{jpg,json}` | Expected to trigger re-capture. |

---

## Task 1: Scaffolding — directories and xcodegen regeneration

**Files:**
- Create (directories only): `HICOR/Services/OCR/Preprocessing/`, `HICOR/Services/OCR/ROI/`, `HICORTests/OCR/Preprocessing/`, `HICORTests/OCR/ROI/`, `HICORTests/OCR/Fixtures/Images/grk6000/dim_good_framing/`, `.../dim_tilted/`, `.../bright_good_framing/`, `.../dim_poor_framing/`.
- Create (placeholder): `HICORTests/OCR/Fixtures/Images/grk6000/.gitkeep`

- [ ] **Step 1: Create directories.**

Run:
```bash
mkdir -p HICOR/Services/OCR/Preprocessing \
         HICOR/Services/OCR/ROI \
         HICORTests/OCR/Preprocessing \
         HICORTests/OCR/ROI \
         HICORTests/OCR/Fixtures/Images/grk6000/dim_good_framing \
         HICORTests/OCR/Fixtures/Images/grk6000/dim_tilted \
         HICORTests/OCR/Fixtures/Images/grk6000/bright_good_framing \
         HICORTests/OCR/Fixtures/Images/grk6000/dim_poor_framing
touch HICORTests/OCR/Fixtures/Images/grk6000/.gitkeep
```

- [ ] **Step 2: Regenerate project and re-integrate Pods.**

Run: `xcodegen generate && pod install`
Expected: `Generated project successfully.` then `Pod installation complete!`

- [ ] **Step 3: Sanity build.**

Run: `xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit.**

```bash
git add HICOR/Services/OCR/Preprocessing HICOR/Services/OCR/ROI \
        HICORTests/OCR/Preprocessing HICORTests/OCR/ROI \
        HICORTests/OCR/Fixtures/Images/grk6000 HICOR.xcodeproj
git commit -m "chore: scaffold ROI pipeline directories"
```

---

## Task 2: ImageEnhancer — Core Image contrast/gamma/unsharp

**Files:**
- Create: `HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift`
- Create: `HICORTests/OCR/Preprocessing/ImageEnhancerTests.swift`

- [ ] **Step 1: Write the failing test.**

Create `HICORTests/OCR/Preprocessing/ImageEnhancerTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

final class ImageEnhancerTests: XCTestCase {

    private func flatGrayImage(value: UInt8, size: CGSize = CGSize(width: 40, height: 40)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: CGFloat(value) / 255.0,
                    green: CGFloat(value) / 255.0,
                    blue: CGFloat(value) / 255.0,
                    alpha: 1.0).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func centerPixelLuminance(_ image: UIImage) -> UInt8 {
        let cg = image.cgImage!
        let width = cg.width, height = cg.height
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(data: &pixel,
                            width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: colorSpace, bitmapInfo: bitmap.rawValue)!
        ctx.draw(cg, in: CGRect(x: -CGFloat(width / 2),
                                y: -CGFloat(height / 2),
                                width: CGFloat(width),
                                height: CGFloat(height)))
        return pixel[0]
    }

    func testStandardEnhancementLiftsDarkPixelsAndPushesLightsHigher() {
        let dark = flatGrayImage(value: 70)
        let light = flatGrayImage(value: 200)

        let darkOut = ImageEnhancer.enhance(dark, strength: .standard)
        let lightOut = ImageEnhancer.enhance(light, strength: .standard)

        XCTAssertGreaterThan(centerPixelLuminance(darkOut), 70,
                             "gamma < 1.0 should lift dark pixels")
        XCTAssertGreaterThanOrEqual(centerPixelLuminance(lightOut), 200,
                                    "light pixels should not darken")
    }

    func testAggressiveEnhancementLiftsMoreThanStandard() {
        let dark = flatGrayImage(value: 70)

        let standard = centerPixelLuminance(ImageEnhancer.enhance(dark, strength: .standard))
        let aggressive = centerPixelLuminance(ImageEnhancer.enhance(dark, strength: .aggressive))

        XCTAssertGreaterThan(aggressive, standard,
                             "aggressive should lift dark pixels more than standard")
    }

    func testEnhancementPreservesImageSize() {
        let input = flatGrayImage(value: 128, size: CGSize(width: 60, height: 40))
        let output = ImageEnhancer.enhance(input, strength: .standard)
        XCTAssertEqual(output.size, CGSize(width: 60, height: 40))
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build-for-testing CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: Compile errors citing `cannot find 'ImageEnhancer' in scope`.

- [ ] **Step 3: Implement ImageEnhancer.**

Create `HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift`:

```swift
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageEnhancer {

    enum Strength {
        case standard
        case aggressive
    }

    static func enhance(_ image: UIImage, strength: Strength = .standard) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let ciInput = CIImage(cgImage: cg)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        let contrast: Double
        let brightness: Double
        let gammaPower: Double
        let unsharpRadius: Double
        let unsharpIntensity: Double

        switch strength {
        case .standard:
            contrast = 1.3
            brightness = 0.05
            gammaPower = 0.7
            unsharpRadius = 2.0
            unsharpIntensity = 0.5
        case .aggressive:
            contrast = 1.6
            brightness = 0.10
            gammaPower = 0.5
            unsharpRadius = 2.5
            unsharpIntensity = 0.8
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciInput
        colorControls.contrast = Float(contrast)
        colorControls.brightness = Float(brightness)
        colorControls.saturation = 1.0

        guard let afterColor = colorControls.outputImage else { return image }

        let gamma = CIFilter.gammaAdjust()
        gamma.inputImage = afterColor
        gamma.power = Float(gammaPower)

        guard let afterGamma = gamma.outputImage else { return image }

        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = afterGamma
        sharpen.radius = Float(unsharpRadius)
        sharpen.intensity = Float(unsharpIntensity)

        guard let finalCI = sharpen.outputImage else { return image }

        // Preserve original extent so output size matches input.
        let extent = ciInput.extent
        guard let cgOut = context.createCGImage(finalCI, from: extent) else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }
}
```

- [ ] **Step 4: Regenerate project and run tests.**

Run:
```bash
xcodegen generate && pod install
xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:HICORTests/ImageEnhancerTests 2>&1 | tail -20
```
Expected: `Test Suite 'ImageEnhancerTests' passed`, three tests passing.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Services/OCR/Preprocessing/ImageEnhancer.swift \
        HICORTests/OCR/Preprocessing/ImageEnhancerTests.swift \
        HICOR.xcodeproj
git commit -m "feat: ImageEnhancer with standard and aggressive Core Image pipelines"
```

---

## Task 3: DocumentRectifier — Vision rectangle detection + perspective warp

**Files:**
- Create: `HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift`
- Create: `HICORTests/OCR/Preprocessing/DocumentRectifierTests.swift`

- [ ] **Step 1: Write the failing tests.**

Create `HICORTests/OCR/Preprocessing/DocumentRectifierTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

final class DocumentRectifierTests: XCTestCase {

    /// Draw a dark rectangle on a light background at the given normalized
    /// coordinates (Vision-style, origin bottom-left, 0..1). Vision has no
    /// trouble detecting this kind of high-contrast quad.
    private func imageWithRect(
        rectNormalized: CGRect,
        imageSize: CGSize = CGSize(width: 600, height: 800)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: imageSize).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: imageSize))
            UIColor.black.setFill()
            let pixelRect = CGRect(
                x: rectNormalized.minX * imageSize.width,
                // Flip Y: we pass normalized bottom-left, draw top-left.
                y: (1.0 - rectNormalized.maxY) * imageSize.height,
                width: rectNormalized.width * imageSize.width,
                height: rectNormalized.height * imageSize.height
            )
            ctx.fill(pixelRect)
        }
    }

    func testRectifyReturnsImageWhenPrintoutFillsFrame() async {
        let image = imageWithRect(rectNormalized: CGRect(x: 0.1, y: 0.15, width: 0.8, height: 0.7))
        let out = await DocumentRectifier.rectify(image)
        XCTAssertNotNil(out)
    }

    func testRectifyReturnsNilWhenNoRectanglePresent() async {
        // A flat gray image has no detectable rectangle.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        let out = await DocumentRectifier.rectify(image)
        XCTAssertNil(out)
    }

    func testRectifyOutputIsLongSideHorizontal() async {
        // Tall rectangle in a tall source image. Expect output to be
        // wider-than-tall (normalized to long-side-horizontal).
        let image = imageWithRect(
            rectNormalized: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8),
            imageSize: CGSize(width: 600, height: 1000)
        )
        guard let out = await DocumentRectifier.rectify(image) else {
            return XCTFail("expected rectification to succeed")
        }
        XCTAssertGreaterThanOrEqual(out.size.width, out.size.height,
                                    "rectified image should be normalized to landscape")
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO -only-testing:HICORTests/DocumentRectifierTests 2>&1 | tail -5`
Expected: `cannot find 'DocumentRectifier' in scope`.

- [ ] **Step 3: Implement DocumentRectifier.**

Create `HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift`:

```swift
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

enum DocumentRectifier {

    /// Detects the printout rectangle in `image` and returns a perspective-
    /// corrected UIImage normalized to long-side-horizontal orientation.
    /// Returns nil when no suitable rectangle is found.
    static func rectify(_ image: UIImage) async -> UIImage? {
        guard let cg = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.7
        request.minimumAspectRatio = 0.5
        request.maximumAspectRatio = 2.0
        request.maximumObservations = 8

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        // Select: biggest rectangle whose center is in the inner 70% of the
        // frame. Biases toward the framing guide, against background clutter.
        let innerRect = CGRect(x: 0.15, y: 0.15, width: 0.70, height: 0.70)
        let eligible = observations.filter { obs in
            innerRect.contains(CGPoint(
                x: (obs.topLeft.x + obs.topRight.x + obs.bottomLeft.x + obs.bottomRight.x) / 4.0,
                y: (obs.topLeft.y + obs.topRight.y + obs.bottomLeft.y + obs.bottomRight.y) / 4.0
            ))
        }
        let pool = eligible.isEmpty ? observations : eligible
        let chosen = pool.max { area($0) < area($1) }!

        let ciInput = CIImage(cgImage: cg)
        let imageSize = ciInput.extent.size

        // Vision returns normalized coords, origin bottom-left.
        // CIPerspectiveCorrection expects pixel coords, origin bottom-left.
        let tl = CGPoint(x: chosen.topLeft.x * imageSize.width,
                         y: chosen.topLeft.y * imageSize.height)
        let tr = CGPoint(x: chosen.topRight.x * imageSize.width,
                         y: chosen.topRight.y * imageSize.height)
        let bl = CGPoint(x: chosen.bottomLeft.x * imageSize.width,
                         y: chosen.bottomLeft.y * imageSize.height)
        let br = CGPoint(x: chosen.bottomRight.x * imageSize.width,
                         y: chosen.bottomRight.y * imageSize.height)

        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = ciInput
        correction.topLeft = tl
        correction.topRight = tr
        correction.bottomLeft = bl
        correction.bottomRight = br

        guard let corrected = correction.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgOut = context.createCGImage(corrected, from: corrected.extent) else { return nil }

        let rectified = UIImage(cgImage: cgOut)

        // Normalize to long-side-horizontal.
        if rectified.size.height > rectified.size.width {
            return rotate90CW(rectified)
        }
        return rectified
    }

    private static func area(_ obs: VNRectangleObservation) -> CGFloat {
        let w = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
        let h = hypot(obs.topLeft.x - obs.bottomLeft.x, obs.topLeft.y - obs.bottomLeft.y)
        return w * h
    }

    private static func rotate90CW(_ image: UIImage) -> UIImage {
        let newSize = CGSize(width: image.size.height, height: image.size.width)
        return UIGraphicsImageRenderer(size: newSize).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width, y: 0)
            cg.rotate(by: .pi / 2)
            image.draw(at: .zero)
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run tests.**

Run:
```bash
xcodegen generate && pod install
xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:HICORTests/DocumentRectifierTests 2>&1 | tail -20
```
Expected: three tests passing.

If the rectangle-detection test fails (Vision can miss synthetic rectangles under some simulator conditions), add a higher-contrast white border around the black rectangle in `imageWithRect` — do not weaken the assertion.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Services/OCR/Preprocessing/DocumentRectifier.swift \
        HICORTests/OCR/Preprocessing/DocumentRectifierTests.swift \
        HICOR.xcodeproj
git commit -m "feat: DocumentRectifier using Vision rect detect + CIPerspectiveCorrection"
```

---

## Task 4: Anchors and CellLayout — geometry types and pure grid math

**Files:**
- Create: `HICOR/Services/OCR/ROI/Anchors.swift`
- Create: `HICOR/Services/OCR/ROI/CellLayout.swift`
- Create: `HICORTests/OCR/ROI/CellLayoutTests.swift`

- [ ] **Step 1: Write the failing tests.**

Create `HICORTests/OCR/ROI/CellLayoutTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

final class CellLayoutTests: XCTestCase {

    /// Build a synthetic Anchors set mimicking a GRK-6000 layout on a
    /// 1500×1100 rectified image. Right section in top half, left in bottom.
    private func syntheticAnchors() -> Anchors {
        let right = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y:  60, width: 60, height: 60),  // <R>
            sph:       CGRect(x:  120, y: 100, width: 80, height: 60),
            cyl:       CGRect(x:  120, y: 240, width: 80, height: 60),
            ax:        CGRect(x:  120, y: 380, width: 80, height: 60),
            avg:       CGRect(x:  120, y: 520, width: 80, height: 60)
        )
        let left = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y: 640, width: 60, height: 60),  // <L>
            sph:       CGRect(x:  120, y: 680, width: 80, height: 60),
            cyl:       CGRect(x:  120, y: 800, width: 80, height: 60),
            ax:        CGRect(x:  120, y: 920, width: 80, height: 60),
            avg:       CGRect(x:  120, y:1040, width: 80, height: 60)
        )
        return Anchors(right: right, left: left)
    }

    func testLayoutProduces24Cells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.count, 24)
    }

    func testEachEyeHas12Cells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.filter { $0.eye == .right }.count, 12)
        XCTAssertEqual(cells.filter { $0.eye == .left }.count, 12)
    }

    func testEachColumnHasEightCells() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        XCTAssertEqual(cells.filter { $0.column == .sph }.count, 8)
        XCTAssertEqual(cells.filter { $0.column == .cyl }.count, 8)
        XCTAssertEqual(cells.filter { $0.column == .ax  }.count, 8)
    }

    func testRowKindsPerEye() {
        let cells = CellLayout.grk6000Desktop.cells(given: syntheticAnchors())
        for eye in [CellROI.Eye.right, .left] {
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                let count = cells.filter { $0.eye == eye && $0.row == row }.count
                XCTAssertEqual(count, 3, "eye=\(eye) row=\(row) should have 3 cells (one per column)")
            }
        }
    }

    func testSPHCellsAlignHorizontallyWithSPHHeader() {
        let anchors = syntheticAnchors()
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        for cell in cells where cell.eye == .right && cell.column == .sph {
            let sphHeaderMidX = anchors.right.sph.midX
            XCTAssertEqual(cell.rect.midX, sphHeaderMidX, accuracy: 1.0,
                           "SPH cells should share X with SPH header")
        }
    }

    func testRightEyeRowsAreOrderedTopToBottom() {
        let anchors = syntheticAnchors()
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        let rightSPH = cells
            .filter { $0.eye == .right && $0.column == .sph }
            .sorted { rowOrder($0.row) < rowOrder($1.row) }
        // r1 above r2 above r3 above avg → minY ascending
        let minYs = rightSPH.map(\.rect.minY)
        XCTAssertEqual(minYs, minYs.sorted(), "right-eye SPH rows should ascend in Y")
    }

    private func rowOrder(_ row: CellROI.Row) -> Int {
        switch row {
        case .r1:  return 0
        case .r2:  return 1
        case .r3:  return 2
        case .avg: return 3
        }
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild test ... -only-testing:HICORTests/CellLayoutTests 2>&1 | tail -5`
Expected: `cannot find 'CellLayout' in scope` / `cannot find 'Anchors' in scope`.

- [ ] **Step 3: Implement Anchors types.**

Create `HICOR/Services/OCR/ROI/Anchors.swift`:

```swift
import CoreGraphics

struct SectionAnchors: Equatable {
    let eyeMarker: CGRect   // <R>/[R] or <L>/[L]
    let sph: CGRect
    let cyl: CGRect
    let ax: CGRect
    let avg: CGRect
}

struct Anchors: Equatable {
    let right: SectionAnchors
    let left: SectionAnchors
}

struct CellROI: Equatable, Hashable {

    enum Eye: String, Equatable, Hashable { case right, left }
    enum Column: String, Equatable, Hashable { case sph, cyl, ax }
    enum Row: String, Equatable, Hashable { case r1, r2, r3, avg }

    let eye: Eye
    let column: Column
    let row: Row
    let rect: CGRect
}
```

- [ ] **Step 4: Implement CellLayout.**

Create `HICOR/Services/OCR/ROI/CellLayout.swift`:

```swift
import CoreGraphics

struct CellLayout {

    /// Hardcoded layout for the GRK-6000 desktop printout. The grid is
    /// expressed entirely in terms of anchor rectangles provided at call
    /// time — no fixed pixel offsets — so the layout self-calibrates per
    /// capture.
    static let grk6000Desktop = CellLayout()

    /// Returns 24 CellROI values (12 per eye) from an Anchors set:
    ///   - column X is centered on the corresponding header anchor
    ///   - row Y is interpolated between the section's SPH-header baseline
    ///     and the section's AVG anchor, divided into 4 equal rows (r1, r2,
    ///     r3, avg). Column header anchors (SPH/CYL/AX) can drift in Y
    ///     across a row on tilted prints; we use their average midY as the
    ///     header baseline.
    func cells(given anchors: Anchors) -> [CellROI] {
        return buildSection(.right, anchors.right) + buildSection(.left, anchors.left)
    }

    private func buildSection(_ eye: CellROI.Eye, _ section: SectionAnchors) -> [CellROI] {
        let headers: [(CellROI.Column, CGRect)] = [
            (.sph, section.sph),
            (.cyl, section.cyl),
            (.ax,  section.ax)
        ]
        let headerMidY = (section.sph.midY + section.cyl.midY + section.ax.midY) / 3.0
        let avgMidY    = section.avg.midY

        // Four row-midYs equally spaced between headerMidY (excluded) and
        // avgMidY. r1 sits one step below the header, r2 two steps, r3 three
        // steps, avg four steps (== avgMidY).
        let rowStep = (avgMidY - headerMidY) / 4.0
        let rowMidYs: [(CellROI.Row, CGFloat)] = [
            (.r1,  headerMidY + rowStep * 1.0),
            (.r2,  headerMidY + rowStep * 2.0),
            (.r3,  headerMidY + rowStep * 3.0),
            (.avg, avgMidY)
        ]

        // Cell width: 1.4× the header width (numbers need more horizontal
        // room than the 3-letter labels). Cell height: 1.2× the header
        // height. These multipliers were chosen to cover the printed data
        // comfortably with ~10% margin that CellROIExtractor then pads.
        var cells: [CellROI] = []
        for (column, header) in headers {
            let cellW = header.width * 1.4
            let cellH = header.height * 1.2
            for (row, midY) in rowMidYs {
                let rect = CGRect(
                    x: header.midX - cellW / 2.0,
                    y: midY - cellH / 2.0,
                    width: cellW,
                    height: cellH
                )
                cells.append(CellROI(eye: eye, column: column, row: row, rect: rect))
            }
        }
        return cells
    }
}
```

- [ ] **Step 5: Run tests.**

Run: `xcodegen generate && pod install && xcodebuild test ... -only-testing:HICORTests/CellLayoutTests 2>&1 | tail -15`
Expected: six tests passing.

- [ ] **Step 6: Commit.**

```bash
git add HICOR/Services/OCR/ROI/Anchors.swift \
        HICOR/Services/OCR/ROI/CellLayout.swift \
        HICORTests/OCR/ROI/CellLayoutTests.swift \
        HICOR.xcodeproj
git commit -m "feat: Anchors types and CellLayout pure grid math"
```

---

## Task 5: CellROIExtractor — pure cropping with padding

**Files:**
- Create: `HICOR/Services/OCR/ROI/CellROIExtractor.swift`
- Create: `HICORTests/OCR/ROI/CellROIExtractorTests.swift`

- [ ] **Step 1: Write the failing tests.**

Create `HICORTests/OCR/ROI/CellROIExtractorTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

final class CellROIExtractorTests: XCTestCase {

    private func solidImage(size: CGSize = CGSize(width: 1000, height: 800)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testCropDimensionsMatchCellRect() {
        let image = solidImage()
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 100, y: 100, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.0)
        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(crops[0].1.size, CGSize(width: 60, height: 40))
    }

    func testCropAppliesPadding() {
        let image = solidImage()
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 100, y: 100, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.1)
        // 10% padding on each side → 20% wider, 20% taller.
        XCTAssertEqual(crops[0].1.size.width, 60 * 1.2, accuracy: 1.0)
        XCTAssertEqual(crops[0].1.size.height, 40 * 1.2, accuracy: 1.0)
    }

    func testCropClampsToImageBounds() {
        let image = solidImage(size: CGSize(width: 200, height: 200))
        let cell = CellROI(eye: .right, column: .sph, row: .r1,
                           rect: CGRect(x: 180, y: 180, width: 60, height: 40))
        let crops = CellROIExtractor.crop(image: image, cells: [cell], paddingFraction: 0.0)
        // Right/bottom edges clamp: width = 200 - 180 = 20, height = 200 - 180 = 20.
        XCTAssertEqual(crops[0].1.size.width, 20, accuracy: 1.0)
        XCTAssertEqual(crops[0].1.size.height, 20, accuracy: 1.0)
    }

    func testCropPreservesOrder() {
        let image = solidImage()
        let cells = [
            CellROI(eye: .right, column: .sph, row: .r1, rect: CGRect(x: 10, y: 10, width: 20, height: 20)),
            CellROI(eye: .right, column: .cyl, row: .r2, rect: CGRect(x: 50, y: 50, width: 20, height: 20)),
            CellROI(eye: .left,  column: .ax,  row: .avg, rect: CGRect(x: 90, y: 90, width: 20, height: 20))
        ]
        let crops = CellROIExtractor.crop(image: image, cells: cells, paddingFraction: 0.0)
        XCTAssertEqual(crops.map(\.0), cells)
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild test ... -only-testing:HICORTests/CellROIExtractorTests 2>&1 | tail -5`
Expected: `cannot find 'CellROIExtractor' in scope`.

- [ ] **Step 3: Implement CellROIExtractor.**

Create `HICOR/Services/OCR/ROI/CellROIExtractor.swift`:

```swift
import UIKit
import CoreGraphics

enum CellROIExtractor {

    /// Crops each cell rectangle from `image` with `paddingFraction` expansion
    /// on every side. Rectangles are clamped to the image bounds so crops
    /// near the edge return smaller images rather than empty ones.
    static func crop(
        image: UIImage,
        cells: [CellROI],
        paddingFraction: CGFloat = 0.1
    ) -> [(CellROI, UIImage)] {
        guard let cg = image.cgImage else { return [] }
        let imageBounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        var out: [(CellROI, UIImage)] = []
        for cell in cells {
            let padded = cell.rect.insetBy(
                dx: -cell.rect.width * paddingFraction,
                dy: -cell.rect.height * paddingFraction
            )
            let clamped = padded.intersection(imageBounds).integral
            if clamped.isEmpty { continue }
            guard let cropped = cg.cropping(to: clamped) else { continue }
            out.append((cell, UIImage(cgImage: cropped,
                                       scale: image.scale,
                                       orientation: image.imageOrientation)))
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests.**

Run: `xcodegen generate && pod install && xcodebuild test ... -only-testing:HICORTests/CellROIExtractorTests 2>&1 | tail -10`
Expected: four tests passing.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Services/OCR/ROI/CellROIExtractor.swift \
        HICORTests/OCR/ROI/CellROIExtractorTests.swift \
        HICOR.xcodeproj
git commit -m "feat: CellROIExtractor pure crop with padding and edge clamping"
```

---

## Task 6: LineRecognizing protocol + MLKitLineRecognizer wrapper

**Files:**
- Create: `HICOR/Services/OCR/ROI/LineRecognizing.swift`

(No unit test file for this task — it's a one-line protocol plus a thin wrapper around ML Kit. Exercised by downstream tests via stubs.)

- [ ] **Step 1: Create the protocol and wrapper.**

Create `HICOR/Services/OCR/ROI/LineRecognizing.swift`:

```swift
import UIKit
import MLKitTextRecognition
import MLKitVision

/// One line of text recognized by an OCR engine. Frames are in the source
/// image's pixel coordinate space (origin top-left).
struct OCRLine: Equatable {
    let text: String
    let frame: CGRect
}

/// Abstraction over ML Kit's TextRecognizer that lets tests stub the OCR
/// engine without booting the real ML Kit runtime.
protocol LineRecognizing {
    func recognize(_ image: UIImage) async throws -> [OCRLine]
}

final class MLKitLineRecognizer: LineRecognizing {

    enum RecognizerError: Error {
        case noResult
        case failed(Error)
    }

    private let recognizer: TextRecognizer

    init(recognizer: TextRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions())) {
        self.recognizer = recognizer
    }

    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        let text: Text = try await withCheckedThrowingContinuation { cont in
            recognizer.process(visionImage) { text, error in
                if let error { cont.resume(throwing: RecognizerError.failed(error)); return }
                guard let text else { cont.resume(throwing: RecognizerError.noResult); return }
                cont.resume(returning: text)
            }
        }
        return text.blocks.flatMap { block in
            block.lines.map { OCRLine(text: $0.text, frame: $0.frame) }
        }
    }
}
```

- [ ] **Step 2: Build.**

Run: `xcodegen generate && pod install && xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git add HICOR/Services/OCR/ROI/LineRecognizing.swift HICOR.xcodeproj
git commit -m "feat: LineRecognizing protocol and MLKit wrapper for injection"
```

---

## Task 7: AnchorDetector — locate anchors, group by section

**Files:**
- Create: `HICOR/Services/OCR/ROI/AnchorDetector.swift`
- Create: `HICORTests/OCR/ROI/AnchorDetectorTests.swift`

- [ ] **Step 1: Write the failing tests.**

Create `HICORTests/OCR/ROI/AnchorDetectorTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

/// Canned LineRecognizing stub for tests.
private struct StubLineRecognizer: LineRecognizing {
    let lines: [OCRLine]
    func recognize(_ image: UIImage) async throws -> [OCRLine] { lines }
}

final class AnchorDetectorTests: XCTestCase {

    private func blankImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1100)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1100))
        }
    }

    // Layout matches CellLayoutTests.syntheticAnchors(): right section in
    // top half (Y 0-600), left section in bottom half (Y 600-1100).
    private func fullLineSet() -> [OCRLine] {
        [
            OCRLine(text: "<R>", frame: CGRect(x: 1340, y:  60, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  120, y: 100, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  120, y: 240, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x:  120, y: 380, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  120, y: 520, width: 80, height: 60)),

            OCRLine(text: "<L>", frame: CGRect(x: 1340, y: 640, width: 60, height: 60)),
            OCRLine(text: "SPH", frame: CGRect(x:  120, y: 680, width: 80, height: 60)),
            OCRLine(text: "CYL", frame: CGRect(x:  120, y: 800, width: 80, height: 60)),
            OCRLine(text: "AX",  frame: CGRect(x:  120, y: 920, width: 80, height: 60)),
            OCRLine(text: "AVG", frame: CGRect(x:  120, y:1040, width: 80, height: 60))
        ]
    }

    func testDetectAllAnchorsProducesRightAndLeftSections() async throws {
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: fullLineSet()))
        let anchors = try await detector.detectAnchors(in: blankImage())
        XCTAssertEqual(anchors.right.sph.origin.y, 100)
        XCTAssertEqual(anchors.left.sph.origin.y,  680)
    }

    func testAcceptsBracketStyleVariants() async throws {
        var lines = fullLineSet()
        // Swap <R>/<L> for [R]/[L] to test case-insensitive match on both.
        lines[0] = OCRLine(text: "[R]", frame: lines[0].frame)
        lines[5] = OCRLine(text: "[L]", frame: lines[5].frame)
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        _ = try await detector.detectAnchors(in: blankImage())
    }

    func testThrowsInsufficientAnchorsWhenRightSectionMissingMultiple() async {
        var lines = fullLineSet()
        lines.removeAll { $0.text == "SPH" && $0.frame.origin.y < 600 }
        lines.removeAll { $0.text == "CYL" && $0.frame.origin.y < 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        do {
            _ = try await detector.detectAnchors(in: blankImage())
            XCTFail("expected throw")
        } catch AnchorDetector.Error.insufficientAnchors(let missing) {
            XCTAssertTrue(missing.contains(where: { $0.contains("SPH") }))
            XCTAssertTrue(missing.contains(where: { $0.contains("CYL") }))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testInterpolatesSingleMissingAnchor() async throws {
        var lines = fullLineSet()
        // Drop the right-section CYL anchor. Single missing → interpolate
        // from SPH and AX.
        lines.removeAll { $0.text == "CYL" && $0.frame.origin.y < 600 }
        let detector = AnchorDetector(recognizer: StubLineRecognizer(lines: lines))
        let anchors = try await detector.detectAnchors(in: blankImage())
        // SPH at y=100, AX at y=380. Midpoint → y≈240.
        XCTAssertEqual(anchors.right.cyl.midY, 270, accuracy: 30)
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild test ... -only-testing:HICORTests/AnchorDetectorTests 2>&1 | tail -5`
Expected: `cannot find 'AnchorDetector' in scope`.

- [ ] **Step 3: Implement AnchorDetector.**

Create `HICOR/Services/OCR/ROI/AnchorDetector.swift`:

```swift
import UIKit

final class AnchorDetector {

    enum Error: Swift.Error, Equatable {
        case insufficientAnchors(missing: [String])
    }

    private let recognizer: LineRecognizing

    init(recognizer: LineRecognizing) {
        self.recognizer = recognizer
    }

    func detectAnchors(in image: UIImage) async throws -> Anchors {
        let lines = try await recognizer.recognize(image)

        // Locate eye markers first — they set the vertical bands.
        guard let rMarker = lines.first(where: { matchesRightMarker($0.text) }) else {
            throw Error.insufficientAnchors(missing: ["<R>"])
        }
        guard let lMarker = lines.first(where: { matchesLeftMarker($0.text) }) else {
            throw Error.insufficientAnchors(missing: ["<L>"])
        }

        // Section split: anchors whose midY is closer to rMarker.midY belong
        // to the right section; closer to lMarker.midY belong to the left.
        func sectionFor(_ line: OCRLine) -> Section {
            let dRight = abs(line.frame.midY - rMarker.frame.midY)
            let dLeft  = abs(line.frame.midY - lMarker.frame.midY)
            return dRight <= dLeft ? .right : .left
        }

        var rightSPH: CGRect?, rightCYL: CGRect?, rightAX: CGRect?, rightAVG: CGRect?
        var leftSPH:  CGRect?, leftCYL:  CGRect?, leftAX:  CGRect?, leftAVG:  CGRect?

        for line in lines {
            let upper = line.text.uppercased()
            let section = sectionFor(line)
            switch upper {
            case "SPH":
                if section == .right { rightSPH = line.frame } else { leftSPH = line.frame }
            case "CYL":
                if section == .right { rightCYL = line.frame } else { leftCYL = line.frame }
            case "AX":
                if section == .right { rightAX = line.frame } else { leftAX = line.frame }
            case "AVG":
                if section == .right { rightAVG = line.frame } else { leftAVG = line.frame }
            default:
                continue
            }
        }

        let right = try assembleSection(
            label: "right",
            eyeMarker: rMarker.frame,
            sph: rightSPH, cyl: rightCYL, ax: rightAX, avg: rightAVG
        )
        let left = try assembleSection(
            label: "left",
            eyeMarker: lMarker.frame,
            sph: leftSPH, cyl: leftCYL, ax: leftAX, avg: leftAVG
        )
        return Anchors(right: right, left: left)
    }

    private enum Section { case right, left }

    private func matchesRightMarker(_ text: String) -> Bool {
        let up = text.uppercased().trimmingCharacters(in: .whitespaces)
        return up == "<R>" || up == "[R]"
    }

    private func matchesLeftMarker(_ text: String) -> Bool {
        let up = text.uppercased().trimmingCharacters(in: .whitespaces)
        return up == "<L>" || up == "[L]"
    }

    /// Build a SectionAnchors with single-missing-anchor interpolation.
    /// Any section missing 2+ of {SPH, CYL, AX, AVG} throws.
    private func assembleSection(
        label: String,
        eyeMarker: CGRect,
        sph: CGRect?, cyl: CGRect?, ax: CGRect?, avg: CGRect?
    ) throws -> SectionAnchors {
        let present = [("SPH", sph), ("CYL", cyl), ("AX", ax), ("AVG", avg)]
            .filter { $0.1 != nil }
        if present.count < 3 {
            let missing = [("SPH", sph), ("CYL", cyl), ("AX", ax), ("AVG", avg)]
                .compactMap { $0.1 == nil ? "\(label) \($0.0)" : nil }
            throw Error.insufficientAnchors(missing: missing)
        }

        let resolvedSPH = sph ?? interpolate(target: "SPH", sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedCYL = cyl ?? interpolate(target: "CYL", sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedAX  = ax  ?? interpolate(target: "AX",  sph: sph, cyl: cyl, ax: ax, avg: avg)
        let resolvedAVG = avg ?? interpolate(target: "AVG", sph: sph, cyl: cyl, ax: ax, avg: avg)

        return SectionAnchors(
            eyeMarker: eyeMarker,
            sph: resolvedSPH,
            cyl: resolvedCYL,
            ax:  resolvedAX,
            avg: resolvedAVG
        )
    }

    /// Single-missing interpolation by linear extrapolation on Y. Column
    /// labels on the GRK-6000 are equally spaced (SPH → CYL → AX → AVG),
    /// so missing CYL = midpoint(SPH, AX); missing AX = midpoint(CYL, AVG);
    /// missing SPH = CYL − (AX − CYL); missing AVG = AX + (AX − CYL).
    /// X and size are copied from the adjacent anchor (they don't vary
    /// across a column on the GRK-6000 layout).
    private func interpolate(
        target: String,
        sph: CGRect?, cyl: CGRect?, ax: CGRect?, avg: CGRect?
    ) -> CGRect {
        let template = sph ?? cyl ?? ax ?? avg!
        let size = template.size
        let x = template.origin.x

        let y: CGFloat
        switch target {
        case "SPH":
            // SPH = 2*CYL - AX
            y = 2 * cyl!.minY - ax!.minY
        case "CYL":
            y = (sph!.minY + ax!.minY) / 2.0
        case "AX":
            y = (cyl!.minY + avg!.minY) / 2.0
        case "AVG":
            y = 2 * ax!.minY - cyl!.minY
        default:
            y = template.minY
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
```

- [ ] **Step 4: Run tests.**

Run: `xcodegen generate && pod install && xcodebuild test ... -only-testing:HICORTests/AnchorDetectorTests 2>&1 | tail -15`
Expected: four tests passing.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Services/OCR/ROI/AnchorDetector.swift \
        HICORTests/OCR/ROI/AnchorDetectorTests.swift \
        HICOR.xcodeproj
git commit -m "feat: AnchorDetector with section grouping and single-missing interpolation"
```

---

## Task 8: CellOCR — per-cell recognition with shape validation and one retry

**Files:**
- Create: `HICOR/Services/OCR/ROI/CellOCR.swift`
- Create: `HICORTests/OCR/ROI/CellOCRTests.swift`

- [ ] **Step 1: Write the failing tests.**

Create `HICORTests/OCR/ROI/CellOCRTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

/// Stub that returns different lines on first vs. second call.
private final class ScriptedRecognizer: LineRecognizing {
    var scripted: [[OCRLine]]
    private(set) var callCount = 0
    init(scripted: [[OCRLine]]) { self.scripted = scripted }
    func recognize(_ image: UIImage) async throws -> [OCRLine] {
        defer { callCount += 1 }
        let idx = min(callCount, scripted.count - 1)
        return scripted[idx]
    }
}

final class CellOCRTests: XCTestCase {

    private func dummyImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
    }

    private func cell(_ col: CellROI.Column) -> CellROI {
        CellROI(eye: .right, column: col, row: .r1, rect: CGRect(x: 0, y: 0, width: 60, height: 40))
    }

    func testSPHCellAcceptsSignedDecimal() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "-1.25", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-1.25")
        XCTAssertEqual(recognizer.callCount, 1)
    }

    func testCYLCellAcceptsUnsignedDecimal() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "0.50", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.cyl), image: dummyImage())
        XCTAssertEqual(value, "0.50")
    }

    func testAXCellAcceptsIntegerInRange() async {
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "92", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.ax), image: dummyImage())
        XCTAssertEqual(value, "92")
    }

    func testAXCellRejectsValueOutsideRange() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [OCRLine(text: "999", frame: .zero)],  // first attempt fails shape
            [OCRLine(text: "999", frame: .zero)]   // retry also fails
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.ax), image: dummyImage())
        XCTAssertNil(value)
        XCTAssertEqual(recognizer.callCount, 2, "should retry once then give up")
    }

    func testRetryOnInitialShapeFailSucceeds() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [OCRLine(text: "garbage", frame: .zero)],
            [OCRLine(text: "+1.00",   frame: .zero)]
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "+1.00")
        XCTAssertEqual(recognizer.callCount, 2)
    }

    func testPrefersHighestConfidenceLineWithValidShape() async {
        // ML Kit sometimes emits multiple lines for a cell; the implementation
        // should prefer the first one that passes shape validation.
        let recognizer = ScriptedRecognizer(scripted: [[
            OCRLine(text: "junk", frame: .zero),
            OCRLine(text: "-2.25", frame: .zero),
            OCRLine(text: "also-junk", frame: .zero)
        ]])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-2.25")
        XCTAssertEqual(recognizer.callCount, 1, "no retry needed")
    }

    func testEmptyResultTriggersRetry() async {
        let recognizer = ScriptedRecognizer(scripted: [
            [],
            [OCRLine(text: "-0.25", frame: .zero)]
        ])
        let ocr = CellOCR(recognizer: recognizer)
        let value = await ocr.read(cell: cell(.sph), image: dummyImage())
        XCTAssertEqual(value, "-0.25")
        XCTAssertEqual(recognizer.callCount, 2)
    }
}
```

- [ ] **Step 2: Verify the test fails to compile.**

Run: `xcodebuild test ... -only-testing:HICORTests/CellOCRTests 2>&1 | tail -5`
Expected: `cannot find 'CellOCR' in scope`.

- [ ] **Step 3: Implement CellOCR.**

Create `HICOR/Services/OCR/ROI/CellOCR.swift`:

```swift
import UIKit

final class CellOCR {

    private let recognizer: LineRecognizing
    private let enhance: (UIImage, ImageEnhancer.Strength) -> UIImage

    init(
        recognizer: LineRecognizing,
        enhance: @escaping (UIImage, ImageEnhancer.Strength) -> UIImage = ImageEnhancer.enhance
    ) {
        self.recognizer = recognizer
        self.enhance = enhance
    }

    /// Reads one cell. Runs ML Kit on the crop; if no line passes the
    /// column-appropriate shape check, re-runs on an aggressively enhanced
    /// copy of the crop. Returns the first passing value, or nil after the
    /// single retry also fails.
    func read(cell: CellROI, image: UIImage) async -> String? {
        if let value = await attempt(cell: cell, image: image) { return value }
        let harder = enhance(image, .aggressive)
        return await attempt(cell: cell, image: harder)
    }

    private func attempt(cell: CellROI, image: UIImage) async -> String? {
        guard let lines = try? await recognizer.recognize(image) else { return nil }
        for line in lines {
            let candidate = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if matchesShape(candidate, for: cell.column) {
                return candidate
            }
        }
        return nil
    }

    private func matchesShape(_ value: String, for column: CellROI.Column) -> Bool {
        switch column {
        case .sph, .cyl:
            return CellOCR.decimalRegex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ) != nil
        case .ax:
            guard let n = Int(value) else { return false }
            return n >= 1 && n <= 180
        }
    }

    private static let decimalRegex: NSRegularExpression = {
        // Matches an optional sign followed by 1-2 digits, a dot, and exactly
        // two decimal digits. Covers both "-1.25" (SPH) and "0.50" (CYL,
        // where ReadingNormalizer reinserts the minus sign if needed).
        try! NSRegularExpression(pattern: #"^[-+]?\d{1,2}\.\d{2}$"#)
    }()
}
```

- [ ] **Step 4: Run tests.**

Run: `xcodegen generate && pod install && xcodebuild test ... -only-testing:HICORTests/CellOCRTests 2>&1 | tail -15`
Expected: seven tests passing.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Services/OCR/ROI/CellOCR.swift \
        HICORTests/OCR/ROI/CellOCRTests.swift \
        HICOR.xcodeproj
git commit -m "feat: CellOCR with column shape validation and one enhancement retry"
```

---

## Task 9: ROIPipelineExtractor — orchestrator with fallback and all-or-nothing gate

**Files:**
- Create: `HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift`
- Create: `HICORTests/OCR/ROI/ROIPipelineExtractorTests.swift`
- Modify: `HICOR/Services/OCR/OCRService.swift` (add `OCRError.incompleteCells` case only; default extractor swap is Task 13)

- [ ] **Step 1: Add the new OCRError case.**

Edit `HICOR/Services/OCR/OCRService.swift`:

Replace the existing `OCRError` enum (currently lines 118-122) with:

```swift
enum OCRError: Error, Equatable {
    case noTextFound
    case unrecognizedFormat
    case insufficientReadings
    case incompleteCells(missing: [String])
}
```

- [ ] **Step 2: Write the failing tests.**

Create `HICORTests/OCR/ROI/ROIPipelineExtractorTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

/// Stubs everything the orchestrator calls through: rectifier, enhancer,
/// anchor detector, per-cell OCR, fallback extractor.
private final class StubAnchorDetector: AnchorDetector {
    let result: Result<Anchors, Error>
    init(result: Result<Anchors, Error>) {
        self.result = result
        super.init(recognizer: PassthroughRecognizer())
    }
    override func detectAnchors(in image: UIImage) async throws -> Anchors {
        switch result {
        case .success(let a): return a
        case .failure(let e): throw e
        }
    }
}

private struct PassthroughRecognizer: LineRecognizing {
    func recognize(_ image: UIImage) async throws -> [OCRLine] { [] }
}

private final class ScriptedCellOCR: CellOCR {
    let table: [CellROI: String?]
    init(table: [CellROI: String?]) {
        self.table = table
        super.init(recognizer: PassthroughRecognizer())
    }
    override func read(cell: CellROI, image: UIImage) async -> String? {
        table[cell] ?? nil
    }
}

private final class StubFallback: TextExtracting {
    let output: ExtractedText
    private(set) var callCount = 0
    init(output: ExtractedText) { self.output = output }
    func extractText(from image: UIImage) async throws -> ExtractedText {
        callCount += 1
        return output
    }
}

final class ROIPipelineExtractorTests: XCTestCase {

    private func blankImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1100)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1100))
        }
    }

    private func syntheticAnchors() -> Anchors {
        let right = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y:  60, width: 60, height: 60),
            sph: CGRect(x: 120, y: 100, width: 80, height: 60),
            cyl: CGRect(x: 120, y: 240, width: 80, height: 60),
            ax:  CGRect(x: 120, y: 380, width: 80, height: 60),
            avg: CGRect(x: 120, y: 520, width: 80, height: 60))
        let left = SectionAnchors(
            eyeMarker: CGRect(x: 1340, y: 640, width: 60, height: 60),
            sph: CGRect(x: 120, y: 680, width: 80, height: 60),
            cyl: CGRect(x: 120, y: 800, width: 80, height: 60),
            ax:  CGRect(x: 120, y: 920, width: 80, height: 60),
            avg: CGRect(x: 120, y:1040, width: 80, height: 60))
        return Anchors(right: right, left: left)
    }

    /// Build the 24-cell value table so every cell reads a known value.
    private func fullCellTable(anchors: Anchors) -> [CellROI: String?] {
        let cells = CellLayout.grk6000Desktop.cells(given: anchors)
        var table: [CellROI: String?] = [:]
        for cell in cells {
            switch cell.column {
            case .sph: table[cell] = "-1.25"
            case .cyl: table[cell] = "0.25"
            case .ax:  table[cell] = "92"
            }
        }
        return table
    }

    func testHappyPathProducesRowBasedLines() async throws {
        let anchors = syntheticAnchors()
        let extractor = ROIPipelineExtractor(
            rectify: { _ in self.blankImage() },
            enhance: { image, _ in image },
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: fullCellTable(anchors: anchors)),
            fallback: StubFallback(output: .empty)
        )
        let text = try await extractor.extractText(from: blankImage())
        XCTAssertTrue(text.rowBased.contains("[R]"))
        XCTAssertTrue(text.rowBased.contains("[L]"))
        XCTAssertTrue(text.rowBased.contains("-1.25 0.25 92"))
        XCTAssertTrue(text.rowBased.contains("AVG -1.25 0.25 92"))
    }

    func testRectifyNilDelegatesToFallback() async throws {
        let fallback = StubFallback(output: ExtractedText(
            rowBased: ["[R]", "-1.25 -0.50 108"], columnBased: []))
        let extractor = ROIPipelineExtractor(
            rectify: { _ in nil },
            enhance: { image, _ in image },
            anchorDetector: StubAnchorDetector(
                result: .failure(AnchorDetector.Error.insufficientAnchors(missing: []))),
            cellOCR: ScriptedCellOCR(table: [:]),
            fallback: fallback
        )
        do {
            _ = try await extractor.extractText(from: blankImage())
            XCTFail("expected incomplete-cells throw (fallback lacks full cell set)")
        } catch OCRService.OCRError.incompleteCells {
            XCTAssertEqual(fallback.callCount, 1)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAnchorThrowDelegatesToFallback() async {
        let fallback = StubFallback(output: .empty)
        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            anchorDetector: StubAnchorDetector(
                result: .failure(AnchorDetector.Error.insufficientAnchors(missing: ["right SPH"]))),
            cellOCR: ScriptedCellOCR(table: [:]),
            fallback: fallback
        )
        do {
            _ = try await extractor.extractText(from: blankImage())
            XCTFail("expected throw")
        } catch OCRService.OCRError.incompleteCells {
            XCTAssertEqual(fallback.callCount, 1)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAnyMissingCellThrowsIncompleteCells() async {
        let anchors = syntheticAnchors()
        var table = fullCellTable(anchors: anchors)
        // Drop a single cell → nil.
        let firstKey = table.first { $0.value != nil }!.key
        table[firstKey] = .some(nil)

        let extractor = ROIPipelineExtractor(
            rectify: { $0 },
            enhance: { image, _ in image },
            anchorDetector: StubAnchorDetector(result: .success(anchors)),
            cellOCR: ScriptedCellOCR(table: table),
            fallback: StubFallback(output: .empty)
        )
        do {
            _ = try await extractor.extractText(from: blankImage())
            XCTFail("expected throw")
        } catch OCRService.OCRError.incompleteCells(let missing) {
            XCTAssertFalse(missing.isEmpty)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

- [ ] **Step 3: Verify tests fail to compile.**

Run: `xcodebuild test ... -only-testing:HICORTests/ROIPipelineExtractorTests 2>&1 | tail -5`
Expected: `cannot find 'ROIPipelineExtractor' in scope`.

- [ ] **Step 4: Implement ROIPipelineExtractor.**

Create `HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift`:

```swift
import UIKit

final class ROIPipelineExtractor: TextExtracting {

    typealias RectifyFn = (UIImage) async -> UIImage?
    typealias EnhanceFn = (UIImage, ImageEnhancer.Strength) -> UIImage

    private let rectify: RectifyFn
    private let enhance: EnhanceFn
    private let anchorDetector: AnchorDetector
    private let cellOCR: CellOCR
    private let fallback: TextExtracting
    private let layout: CellLayout
    private let paddingFraction: CGFloat

    init(
        rectify: @escaping RectifyFn = DocumentRectifier.rectify,
        enhance: @escaping EnhanceFn = ImageEnhancer.enhance,
        anchorDetector: AnchorDetector? = nil,
        cellOCR: CellOCR? = nil,
        fallback: TextExtracting = MLKitTextExtractor(),
        layout: CellLayout = .grk6000Desktop,
        paddingFraction: CGFloat = 0.10
    ) {
        self.rectify = rectify
        self.enhance = enhance
        let recognizer = MLKitLineRecognizer()
        self.anchorDetector = anchorDetector ?? AnchorDetector(recognizer: recognizer)
        self.cellOCR = cellOCR ?? CellOCR(recognizer: recognizer)
        self.fallback = fallback
        self.layout = layout
        self.paddingFraction = paddingFraction
    }

    func extractText(from image: UIImage) async throws -> ExtractedText {
        // Step 1: rectify. Nil → fallback.
        guard let rectified = await rectify(image) else {
            return try await fallbackOrThrow(image)
        }

        // Step 2: enhance.
        let enhanced = enhance(rectified, .standard)

        // Step 3: anchor detection.
        let anchors: Anchors
        do {
            anchors = try await anchorDetector.detectAnchors(in: enhanced)
        } catch {
            return try await fallbackOrThrow(image)
        }

        // Step 4-5: layout → crops.
        let cells = layout.cells(given: anchors)
        let crops = CellROIExtractor.crop(image: enhanced, cells: cells, paddingFraction: paddingFraction)

        // Step 6: per-cell OCR.
        var values: [CellROI: String] = [:]
        var missing: [String] = []
        for (cell, crop) in crops {
            if let value = await cellOCR.read(cell: cell, image: crop) {
                values[cell] = value
            } else {
                missing.append(cellLabel(cell))
            }
        }
        // Any cell that didn't even get cropped (rectangle fell entirely
        // outside the image bounds) is also missing.
        let croppedSet = Set(crops.map { $0.0 })
        for cell in cells where !croppedSet.contains(cell) {
            missing.append(cellLabel(cell))
        }

        // Step 7: all-or-nothing gate.
        if !missing.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: missing)
        }

        // Step 8: assemble rowBased lines.
        let rowBased = assembleRowLines(values: values)
        return ExtractedText(
            rowBased: rowBased,
            columnBased: rowBased,
            preprocessedImageData: enhanced.jpegData(compressionQuality: 0.85),
            boxes: [],
            revisionUsed: 0,
            variant: .raw
        )
    }

    func extractText(
        from image: UIImage,
        variant: PreprocessingVariant,
        revision: Int
    ) async throws -> ExtractedText {
        // Variant/revision are no-ops for the ROI pipeline (kept for
        // protocol parity).
        try await extractText(from: image)
    }

    // MARK: - Private helpers

    private func fallbackOrThrow(_ image: UIImage) async throws -> ExtractedText {
        let fbText = try await fallback.extractText(from: image)
        // Subject fallback output to the same all-or-nothing gate.
        if fbText.rowBased.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: ["fallback produced no text"])
        }
        let missing = fallbackMissingCells(fbText.rowBased)
        if !missing.isEmpty {
            throw OCRService.OCRError.incompleteCells(missing: missing)
        }
        return fbText
    }

    /// Checks that fallback output contains the expected structure: one
    /// section marker per eye plus four data lines per eye (3 readings + AVG).
    /// Returns a list of human-readable missing-section labels.
    private func fallbackMissingCells(_ lines: [String]) -> [String] {
        var missing: [String] = []
        for (marker, eyeLabel) in [("[R]", "right"), ("[L]", "left")] {
            guard let idx = lines.firstIndex(of: marker) else {
                missing.append("\(eyeLabel) section marker")
                continue
            }
            let sectionEnd = min(idx + 5, lines.count)
            let section = Array(lines[(idx + 1)..<sectionEnd])
            let readingLines = section.filter { !$0.hasPrefix("AVG") && !$0.isEmpty }
            let avgLines = section.filter { $0.hasPrefix("AVG") }
            if readingLines.count < 3 { missing.append("\(eyeLabel) readings (<3)") }
            if avgLines.isEmpty { missing.append("\(eyeLabel) AVG") }
        }
        return missing
    }

    private func assembleRowLines(values: [CellROI: String]) -> [String] {
        var lines: [String] = []
        for eye in [CellROI.Eye.right, .left] {
            lines.append(eye == .right ? "[R]" : "[L]")
            for row in [CellROI.Row.r1, .r2, .r3, .avg] {
                let sph = values[CellROI(eye: eye, column: .sph, row: row, rect: .zero)] ?? ""
                let cyl = values[CellROI(eye: eye, column: .cyl, row: row, rect: .zero)] ?? ""
                let ax  = values[CellROI(eye: eye, column: .ax,  row: row, rect: .zero)] ?? ""
                let prefix = row == .avg ? "AVG " : ""
                lines.append("\(prefix)\(sph) \(cyl) \(ax)")
            }
        }
        return lines
    }

    private func cellLabel(_ cell: CellROI) -> String {
        "\(cell.eye.rawValue) \(cell.column.rawValue) \(cell.row.rawValue)"
    }
}
```

**⚠️ Note on CellROI equality/hashing:** the lookup in `assembleRowLines` constructs a `CellROI` with `rect: .zero` and expects it to match the keys stored in `values` (which have real rectangles). Swift's synthesized `Hashable` will NOT treat these as equal. Fix this in `HICOR/Services/OCR/ROI/Anchors.swift` by implementing `Hashable` manually, keying only on `(eye, column, row)`:

```swift
struct CellROI: Equatable, Hashable {

    enum Eye: String, Equatable, Hashable { case right, left }
    enum Column: String, Equatable, Hashable { case sph, cyl, ax }
    enum Row: String, Equatable, Hashable { case r1, r2, r3, avg }

    let eye: Eye
    let column: Column
    let row: Row
    let rect: CGRect

    static func == (lhs: CellROI, rhs: CellROI) -> Bool {
        lhs.eye == rhs.eye && lhs.column == rhs.column && lhs.row == rhs.row
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(eye)
        hasher.combine(column)
        hasher.combine(row)
    }
}
```

This keeps the identity-level equality that the orchestrator needs. CellLayoutTests still pass because they don't rely on rect in equality checks.

- [ ] **Step 5: Update Anchors.swift CellROI equality.**

Edit `HICOR/Services/OCR/ROI/Anchors.swift` to replace the auto-synthesized `CellROI` equality/hashing with the explicit implementation above.

- [ ] **Step 6: Run all new tests.**

Run:
```bash
xcodegen generate && pod install
xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:HICORTests/ROIPipelineExtractorTests \
  -only-testing:HICORTests/CellLayoutTests \
  -only-testing:HICORTests/CellROIExtractorTests \
  -only-testing:HICORTests/CellOCRTests \
  -only-testing:HICORTests/AnchorDetectorTests 2>&1 | tail -25
```
Expected: all new suites pass, no regressions.

- [ ] **Step 7: Full test sweep to confirm no regressions in existing suites.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: all prior suites (OCRServiceTests, parser tests, etc.) still pass. The `incompleteCells` case addition is additive — no existing test should reference it.

- [ ] **Step 8: Commit.**

```bash
git add HICOR/Services/OCR/ROI/ROIPipelineExtractor.swift \
        HICOR/Services/OCR/ROI/Anchors.swift \
        HICOR/Services/OCR/OCRService.swift \
        HICORTests/OCR/ROI/ROIPipelineExtractorTests.swift \
        HICOR.xcodeproj
git commit -m "feat: ROIPipelineExtractor orchestrator with all-or-nothing gate and fallback"
```

---

## Task 10: UI wiring — surface `incompleteCells` as a re-capture prompt

**Files:**
- Modify: `HICOR/Views/AnalysisPlaceholderView.swift` (specifically `humanReadable(_ error:)` at lines 225-237)

- [ ] **Step 1: Extend humanReadable.**

Edit `HICOR/Views/AnalysisPlaceholderView.swift`:

Replace the current `humanReadable(_ error:)` function:

```swift
private func humanReadable(_ error: Error) -> String {
    if let ocrError = error as? OCRService.OCRError {
        switch ocrError {
        case .noTextFound:
            return "No text was detected in the photo. Retake it with better lighting."
        case .unrecognizedFormat:
            return "The printout format was not recognized. Confirm the photo shows the autorefractor slip."
        case .insufficientReadings:
            return "Not enough valid readings were extracted. Retake the photo."
        case .incompleteCells(let missing):
            let labels = missing.prefix(3).joined(separator: ", ")
            let suffix = missing.count > 3 ? ", plus \(missing.count - 3) more" : ""
            return "Couldn't read all readings (\(labels)\(suffix)). Retake the photo with the printout well-lit and centered in the frame."
        }
    }
    return error.localizedDescription
}
```

- [ ] **Step 2: Build to confirm compile.**

Run: `xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run full test sweep.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 4: Commit.**

```bash
git add HICOR/Views/AnalysisPlaceholderView.swift
git commit -m "feat: surface OCRError.incompleteCells as a re-capture prompt"
```

---

## Task 11: CaptureView — AVFoundation capture with torch and framing guide

**Files:**
- Create: `HICOR/Views/CaptureView.swift`

No unit tests for this task — AVFoundation behavior is integration-tested on-device in Task 15. An SDK-level unit test would need heavy UI hosting that's not worth the cost for a ~150-line view. If the engineer has doubts, SwiftUI preview manual verification is sufficient.

- [ ] **Step 1: Implement CaptureView.**

Create `HICOR/Views/CaptureView.swift`:

```swift
import SwiftUI
import AVFoundation
import UIKit

/// Full-screen camera capture view with torch toggle and a dashed framing
/// overlay matching the GRK-6000 printout's ~4:3 landscape aspect ratio.
/// Calls `onImagePicked` with the captured UIImage, or `onCancel` when the
/// user backs out.
struct CaptureView: View {

    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var model = CaptureModel()

    var body: some View {
        ZStack {
            CapturePreview(model: model).ignoresSafeArea()

            // Framing guide — 4:3 landscape, 80% width.
            GeometryReader { geo in
                let guideWidth = geo.size.width * 0.9
                let guideHeight = guideWidth * 3.0 / 4.0
                Path { path in
                    let rect = CGRect(
                        x: (geo.size.width - guideWidth) / 2.0,
                        y: (geo.size.height - guideHeight) / 2.0,
                        width: guideWidth,
                        height: guideHeight
                    )
                    path.addRect(rect)
                }
                .stroke(style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .foregroundColor(.white.opacity(0.8))
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    Spacer()
                }
                Spacer()

                HStack {
                    Button(action: { model.toggleTorch() }) {
                        Image(systemName: model.torchOn ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(model.torchAvailable ? .white : .gray)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .disabled(!model.torchAvailable)

                    Spacer()

                    Button(action: {
                        model.capture { image in
                            if let image { onImagePicked(image) }
                        }
                    }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 4)
                                        .frame(width: 84, height: 84))
                    }

                    Spacer().frame(width: 60)   // balance the torch column
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct CapturePreview: UIViewRepresentable {
    let model: CaptureModel
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let layer = AVCaptureVideoPreviewLayer(session: model.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.layer = layer
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.layer?.frame = uiView.bounds
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var layer: AVCaptureVideoPreviewLayer?
    }
}

@MainActor
final class CaptureModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var pendingCompletion: ((UIImage?) -> Void)?

    @Published var torchOn = false
    @Published var torchAvailable = false

    func start() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            device = dev
            torchAvailable = dev.hasTorch
            if let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) {
                session.addInput(input)
            }
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.isHighResolutionCaptureEnabled = true
        }
        session.commitConfiguration()
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    func stop() {
        if torchOn { toggleTorch() }
        session.stopRunning()
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if torchOn {
                device.torchMode = .off
                torchOn = false
            } else {
                try device.setTorchModeOn(level: 1.0)
                torchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            // If torch lock fails, silently leave state unchanged.
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        pendingCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                  didFinishProcessingPhoto photo: AVCapturePhoto,
                                  error: Error?) {
        let image: UIImage? = {
            guard error == nil, let data = photo.fileDataRepresentation() else { return nil }
            return UIImage(data: data)
        }()
        Task { @MainActor in
            self.pendingCompletion?(image)
            self.pendingCompletion = nil
        }
    }
}
```

- [ ] **Step 2: Build.**

Run: `xcodegen generate && pod install && xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**

```bash
git add HICOR/Views/CaptureView.swift HICOR.xcodeproj
git commit -m "feat: CaptureView with AVFoundation preview, torch toggle, framing guide"
```

---

## Task 12: Wire CaptureView into PhotoCaptureView and delete CameraPickerView

**Files:**
- Modify: `HICOR/Views/PhotoCaptureView.swift:37-44`
- Delete: `HICOR/Views/CameraPickerView.swift`

- [ ] **Step 1: Swap the sheet content.**

Edit `HICOR/Views/PhotoCaptureView.swift`:

Replace:
```swift
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { image in
                if let data = image.jpegData(compressionQuality: 0.8) {
                    state.addPhoto(data)
                }
            }
            .ignoresSafeArea()
        }
```

with:

```swift
        .fullScreenCover(isPresented: $showingCamera) {
            CaptureView(
                onImagePicked: { image in
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        state.addPhoto(data)
                    }
                    showingCamera = false
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
```

- [ ] **Step 2: Delete CameraPickerView.**

Run: `rm HICOR/Views/CameraPickerView.swift`

- [ ] **Step 3: Regenerate and build.**

Run: `xcodegen generate && pod install && xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If there's a reference to `CameraPickerView` elsewhere, the build will fail with `cannot find 'CameraPickerView' in scope` — grep the repo for that symbol and fix any leftover usage.

- [ ] **Step 4: Run full test sweep.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 5: Commit.**

```bash
git add HICOR/Views/PhotoCaptureView.swift HICOR.xcodeproj
git rm HICOR/Views/CameraPickerView.swift
git commit -m "refactor: replace CameraPickerView with CaptureView in PhotoCaptureView"
```

---

## Task 13: Switch OCRService default extractor to ROIPipelineExtractor

**Files:**
- Modify: `HICOR/Services/OCR/OCRService.swift:126` (the `init(extractor:)` default parameter)

- [ ] **Step 1: Swap the default.**

Edit `HICOR/Services/OCR/OCRService.swift`:

Replace:
```swift
    init(extractor: TextExtracting = MLKitTextExtractor()) {
        self.extractor = extractor
    }
```

with:

```swift
    init(extractor: TextExtracting = ROIPipelineExtractor(fallback: MLKitTextExtractor())) {
        self.extractor = extractor
    }
```

- [ ] **Step 2: Build.**

Run: `xcodebuild -workspace HICOR.xcworkspace -scheme HICOR -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run full test sweep.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10`
Expected: all tests pass. `OCRServiceTests` uses a `StubExtractor` via the protocol, so swapping the default doesn't affect it.

- [ ] **Step 4: Commit.**

```bash
git add HICOR/Services/OCR/OCRService.swift
git commit -m "feat: switch OCRService default extractor to ROIPipelineExtractor"
```

---

## Task 14: Fixture corpus bootstrap — capture real images and record expected values

This task is a **manual step paired with a codified expected.json schema**. The engineer cannot generate fixture images by themselves — real autorefractor photos from the iPhone are required per the project's "test fixtures use real machine output" rule.

**Files:**
- Create (placeholder README): `HICORTests/OCR/Fixtures/Images/grk6000/README.md`

- [ ] **Step 1: Write the fixture README describing the capture protocol and JSON schema.**

Create `HICORTests/OCR/Fixtures/Images/grk6000/README.md`:

```markdown
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
```

- [ ] **Step 2: Commit the README.**

```bash
git add HICORTests/OCR/Fixtures/Images/grk6000/README.md
git commit -m "docs: GRK-6000 fixture capture protocol and JSON schema"
```

- [ ] **Step 3: USER MANUAL STEP — capture initial fixtures.**

The engineer's work pauses here. Ask the user (scott@theblanfords.com) to:

1. Deploy the current build to their iPhone (signed build via Xcode).
2. Open the app, tap through to the capture view for a test patient.
3. Capture 3+ dim_good_framing photos using torch. Air-drop them to the Mac.
4. Capture 2+ dim_tilted photos (rotate the slip 10-20 degrees relative to the phone).
5. Capture 1-2 bright_good_framing photos (ambient room light, no torch).
6. Capture 1 dim_poor_framing photo (deliberately bad — partially cropped or severe tilt).

Drop the JPEGs into the appropriate `HICORTests/OCR/Fixtures/Images/grk6000/<subdir>/` directory on the Mac, then transcribe the expected values from the physical slip into matching JSON files per the schema above.

- [ ] **Step 4: Verify fixtures are in place.**

Run:
```bash
find HICORTests/OCR/Fixtures/Images/grk6000 -type f \( -name '*.jpg' -o -name '*.json' \) | sort
```
Expected: at least 7 fixture files (4+ JPEGs + 4+ JSON files across the four subdirectories).

- [ ] **Step 5: Commit fixtures.**

```bash
git add HICORTests/OCR/Fixtures/Images/grk6000
git commit -m "test: initial GRK-6000 fixture corpus (user-provided real captures)"
```

---

## Task 15: Layer 2 fixture tests — ROIPipelineFixtureTests

**Files:**
- Create: `HICORTests/OCR/ROI/ROIPipelineFixtureTests.swift`

- [ ] **Step 1: Write the fixture-driven tests.**

Create `HICORTests/OCR/ROI/ROIPipelineFixtureTests.swift`:

```swift
import XCTest
import UIKit
@testable import HICOR

/// End-to-end tests that exercise the full ROI pipeline (with the real ML
/// Kit recognizer) against fixture JPEGs captured from the iPhone. Each
/// fixture has a sibling JSON listing the 24 expected reading values; the
/// test asserts either full match or the expected `incompleteCells` throw.
final class ROIPipelineFixtureTests: XCTestCase {

    struct Expected: Decodable {
        struct Section: Decodable {
            let r1: Reading
            let r2: Reading
            let r3: Reading
            let avg: Reading
        }
        struct Reading: Decodable {
            let sph: String
            let cyl: String
            let ax: String
        }
        struct ExpectedBlock: Decodable {
            let right: Section
            let left: Section
        }
        let expected: ExpectedBlock?
        let shouldFail: Bool
    }

    private let bundle = Bundle(for: ROIPipelineFixtureTests.self)

    private func fixtureURLs(in subdir: String) throws -> [URL] {
        let resourceURL = bundle.url(forResource: "Images/grk6000/\(subdir)", withExtension: nil)
        guard let resourceURL else {
            XCTFail("fixture subdir not found: \(subdir)")
            return []
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil
        )
        return contents.filter { $0.pathExtension.lowercased() == "jpg" }.sorted { $0.path < $1.path }
    }

    private func runPipeline(on jpegURL: URL) async throws -> ExtractedText {
        guard let data = try? Data(contentsOf: jpegURL),
              let image = UIImage(data: data) else {
            throw XCTSkip("unable to load \(jpegURL.lastPathComponent)")
        }
        let extractor = ROIPipelineExtractor()
        return try await extractor.extractText(from: image)
    }

    private func assertMatches(text: ExtractedText, expected: Expected.ExpectedBlock, file: StaticString = #file, line: UInt = #line) {
        let rowBased = text.rowBased
        // Expected block → expected rowBased lines, per the orchestrator's
        // assembly convention.
        func format(_ r: Expected.Reading, avg: Bool) -> String {
            let prefix = avg ? "AVG " : ""
            return "\(prefix)\(r.sph) \(r.cyl) \(r.ax)"
        }

        let expectedLines: [String] = [
            "[R]",
            format(expected.right.r1, avg: false),
            format(expected.right.r2, avg: false),
            format(expected.right.r3, avg: false),
            format(expected.right.avg, avg: true),
            "[L]",
            format(expected.left.r1, avg: false),
            format(expected.left.r2, avg: false),
            format(expected.left.r3, avg: false),
            format(expected.left.avg, avg: true)
        ]
        for expected in expectedLines {
            XCTAssertTrue(rowBased.contains(expected),
                          "missing expected line: \(expected) in \(rowBased)",
                          file: file, line: line)
        }
    }

    private func processSubdir(_ subdir: String, shouldFail: Bool) async throws {
        let urls = try fixtureURLs(in: subdir)
        XCTAssertFalse(urls.isEmpty, "no fixtures in \(subdir)")
        for url in urls {
            let jsonURL = url.deletingPathExtension().appendingPathExtension("json")
            guard let jsonData = try? Data(contentsOf: jsonURL) else {
                XCTFail("missing JSON for \(url.lastPathComponent)")
                continue
            }
            let expected = try JSONDecoder().decode(Expected.self, from: jsonData)
            do {
                let text = try await runPipeline(on: url)
                if shouldFail {
                    XCTFail("\(url.lastPathComponent): expected incompleteCells but pipeline succeeded")
                    continue
                }
                guard let block = expected.expected else {
                    XCTFail("\(url.lastPathComponent): JSON missing expected block"); continue
                }
                assertMatches(text: text, expected: block)
            } catch OCRService.OCRError.incompleteCells {
                if !shouldFail {
                    XCTFail("\(url.lastPathComponent): unexpected incompleteCells")
                }
            } catch {
                XCTFail("\(url.lastPathComponent): unexpected error \(error)")
            }
        }
    }

    func testDimGoodFraming() async throws {
        try await processSubdir("dim_good_framing", shouldFail: false)
    }

    func testDimTilted() async throws {
        try await processSubdir("dim_tilted", shouldFail: false)
    }

    func testBrightGoodFraming() async throws {
        try await processSubdir("bright_good_framing", shouldFail: false)
    }

    func testDimPoorFraming() async throws {
        try await processSubdir("dim_poor_framing", shouldFail: true)
    }
}
```

- [ ] **Step 2: Run the fixture tests.**

Run:
```bash
xcodegen generate && pod install
xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:HICORTests/ROIPipelineFixtureTests 2>&1 | tail -30
```

Expected: all four test methods pass when fixtures exist and JSON matches the captured slips. On failure, the test output shows which expected reading line is missing — compare against what the pipeline produced, check whether JSON transcription is off, whether the fixture image actually contains the values, or whether the pipeline is mis-reading.

- [ ] **Step 3: Commit.**

```bash
git add HICORTests/OCR/ROI/ROIPipelineFixtureTests.swift
git commit -m "test: Layer 2 ROI pipeline fixture tests"
```

---

## Task 16: On-device validation gate

This is the **release gate** — the last task before the feature is considered shippable for the May 1 trip. Must be performed on physical iPhone hardware.

**Criteria (from the spec):**
- 10 distinct captures of the GRK-6000 printout under realistic clinical conditions (refraction-room lighting, torch on, one-handed use).
- ≥9 of 10 must produce all 24 readings with values matching the physical slip.
- 0 of 10 may produce incorrect readings. Re-capture prompts are acceptable; silent wrong data is a regression.
- 1 intentional bad capture (severe tilt / partial crop / non-printout) must produce a re-capture prompt, not partial data or a crash.

- [ ] **Step 1: Install on the physical iPhone.**

Open `HICOR.xcworkspace` in Xcode. Select the physical iPhone as the run destination (same device used for prior testing). Run (⌘R). Confirm the app launches, the capture view appears when requested, and the torch button works.

- [ ] **Step 2: Execute the capture protocol.**

Capture 10 real photos as described above. For each capture:
1. Note whether the pipeline produced readings or a re-capture error.
2. If readings, compare against the physical slip. Record any mismatches.
3. If a re-capture error, record which cells were flagged as missing.

Record the tally in a simple checklist (e.g., paste into the PR description when opening).

- [ ] **Step 3: Execute the bad-capture protocol.**

Capture 1 photo with deliberate framing problems. Confirm the app produces the re-capture prompt rather than a partial prescription or a crash.

- [ ] **Step 4: Add two successful captures to the fixture corpus.**

Pick two of the successful captures and add them to `HICORTests/OCR/Fixtures/Images/grk6000/dim_good_framing/` as regression guards. Add matching JSON files per the schema in Task 14. Commit.

```bash
git add HICORTests/OCR/Fixtures/Images/grk6000/dim_good_framing
git commit -m "test: add two regression-guard fixtures from on-device validation"
```

- [ ] **Step 5: Re-run fixture tests to confirm the new fixtures pass.**

Run: `xcodebuild test ... -only-testing:HICORTests/ROIPipelineFixtureTests 2>&1 | tail -15`
Expected: all pass.

- [ ] **Step 6: Decision point.**

- **If 9+ of 10 captures produced correct readings and 0 were wrong** → feature meets gate. Proceed to PR.
- **If less than 9 correct, or any wrong readings** → feature does not meet gate. Do not merge. Options:
  1. Analyze the failure modes from the debug logs (which cells failed shape, which captures triggered fallback).
  2. Tune `CellLayout` offsets (likely cause: cell rectangles don't cover the actual data positions).
  3. Tune `ImageEnhancer` strengths (likely cause: enhancement isn't lifting dim pixels enough).
  4. Escalate to auto-capture (Option C from the brainstorm) by adding live rectangle detection + auto-shutter to `CaptureView`.
- **If wrong readings appear** — the all-or-nothing gate is failing. This is a correctness bug; block merge and investigate before any further feature work.

---

## Task 17: Rollback documentation

**Files:**
- Modify: `CLAUDE.md` (append to existing file)

- [ ] **Step 1: Append rollback notes.**

Edit `CLAUDE.md` to add a new section near the OCR documentation:

```markdown
## ROI pipeline rollback

The default OCR extractor is `ROIPipelineExtractor(fallback: MLKitTextExtractor())`.
If ROI-based extraction needs to be disabled:

- One-line revert: change `HICOR/Services/OCR/OCRService.swift` init default back to `MLKitTextExtractor()`.
- `ROIPipelineExtractor` and all supporting files (`HICOR/Services/OCR/ROI/`, `HICOR/Services/OCR/Preprocessing/`) can stay in the repo dormant.
- `CaptureView` can be reverted to `CameraPickerView` independently — git history has the original `CameraPickerView.swift` if needed, or re-create the stock `UIImagePickerController` wrapper.

The ROI pipeline is designed to be a pure swap behind the `TextExtracting` protocol: rolling back touches one line of production code.
```

- [ ] **Step 2: Commit.**

```bash
git add CLAUDE.md
git commit -m "docs: ROI pipeline rollback instructions"
```

---

## Final verification

- [ ] **Step 1: Full test sweep one more time.**

Run: `xcodebuild test -workspace HICOR.xcworkspace -scheme HICOR -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: **every** existing test plus every new test green.

- [ ] **Step 2: Confirm no dead files.**

Run: `git ls-files | grep -E '(CameraPickerView)' || echo "clean"`
Expected: `clean`.

- [ ] **Step 3: Confirm rollback path works.**

Temporarily change `OCRService.swift:126` default back to `MLKitTextExtractor()`, build, run the capture flow in the simulator once (or on a recorded fixture), then revert. This confirms the rollback is truly one-line.

- [ ] **Step 4: Open PR.**

Push the branch and open a PR against `main` with the title "Add ROI-based OCR pipeline for GRK-6000" and a description summarizing:
- Goal: 95% OCR accuracy on dim captures.
- Method: Rectify + enhance + anchor-relative ROI + per-cell ML Kit.
- Gate: all-or-nothing extraction with re-capture fallback.
- On-device result: X of 10 captures correct (fill in from Task 16).
- Spec reference: `docs/superpowers/specs/2026-04-18-roi-pipeline-design.md`.

---

## Task ordering rationale

1–6 are bottom-up leaves with real unit tests: ImageEnhancer, DocumentRectifier, CellLayout, CellROIExtractor, LineRecognizing wrapper, AnchorDetector (uses LineRecognizing).

7 (CellOCR) and 8 (orchestrator) wire the leaves together with stub dependencies for testing.

9 (UI wiring) and 11 (CaptureView) are UI-layer changes; CaptureView is deliberately last because the simulator can't meaningfully test AVFoundation torch behavior — the only real validation is on-device in Task 16.

12 (swap default) flips the production switch. Putting it after CaptureView means the build never has the new extractor active without the new capture UI.

13–16 are validation and rollback documentation: fixture corpus bootstrap (needs manual user capture), fixture tests (drives CI regressions), on-device gate (drives the merge decision), rollback doc (safety net).

## Known risks and mitigations (engineer awareness)

- **Rectangle detection can fail on low-contrast backgrounds.** Handled by orchestrator fallback in Task 8; if fallback itself fails, incomplete-cells error prompts re-capture.
- **Anchor grouping can misassign rows when the printout is severely tilted.** Task 16 on-device validation catches this. If it recurs, tune the section-assignment logic in AnchorDetector (currently: closer-of-two eye-marker midYs) to weight by distance rather than nearest-wins.
- **Layout offsets are heuristic.** The 1.4×-width / 1.2×-height multipliers in `CellLayout.buildSection` were chosen from rough visual estimates. First on-device failure mode to investigate is "cells mis-cropped"; adjust the multipliers, re-run Task 15 fixture tests, commit.
- **CaptureView torch interaction with AVFoundation priorities.** On some older devices the torch momentarily shuts off when the shutter fires. If on-device testing shows this, set the torch mode explicitly in `capture()` before firing.
