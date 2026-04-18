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

        let extent = ciInput.extent
        guard let cgOut = context.createCGImage(finalCI, from: extent) else { return image }
        return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
    }
}
