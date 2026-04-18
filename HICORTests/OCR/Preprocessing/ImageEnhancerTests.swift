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
        let w = cg.width
        let h = cg.height
        let bytesPerRow = w * 4
        var pixels = Data(count: h * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        pixels.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
            guard let base = rawPtr.baseAddress else { return }
            guard let ctx = CGContext(
                data: base,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let centerIndex = (h / 2) * bytesPerRow + (w / 2) * 4
        return pixels[centerIndex]
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

    func testHelperReadsFlatGrayInputCorrectly() {
        let mid = flatGrayImage(value: 128)
        let read = centerPixelLuminance(mid)
        XCTAssertEqual(read, 128, accuracy: 2,
                       "centerPixelLuminance should read ~128 from a flat-gray(128) image; got \(read)")
    }

    func testEnhancementPreservesImageSize() {
        let input = flatGrayImage(value: 128, size: CGSize(width: 60, height: 40))
        let output = ImageEnhancer.enhance(input, strength: .standard)
        XCTAssertEqual(output.size, CGSize(width: 60, height: 40))
    }

}
