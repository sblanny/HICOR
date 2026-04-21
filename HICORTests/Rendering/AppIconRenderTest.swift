#if DEBUG
import XCTest
import SwiftUI
@testable import HICOR

/// One-shot icon emitter. Disabled by default so CI and normal test runs skip it.
/// To regenerate the app icon PNG, rename `disabled_testRenderAppIcon` to
/// `testRenderAppIcon`, run just this test, then rename it back.
final class AppIconRenderTest: XCTestCase {
    @MainActor
    func disabled_testRenderAppIcon() throws {
        let view = CLEARLogo(size: 1024, fillCanvas: true)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        let ui = try XCTUnwrap(renderer.uiImage, "ImageRenderer failed to produce a UIImage")
        let data = try XCTUnwrap(ui.pngData(), "UIImage had no PNG representation")

        guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
            XCTFail("SRCROOT not set — run this test from Xcode or xcodebuild so the path is defined")
            return
        }
        let outPath = "\(srcRoot)/HICOR/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png"
        try data.write(to: URL(fileURLWithPath: outPath))
        print("Wrote icon to \(outPath) — size \(data.count) bytes")
    }
}
#endif
