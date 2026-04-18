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
