import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

extension CIImage {
    /// Returns a resized image.
    func resized(to size: CGSize) -> CIImage {
        let outputScaleX = size.width / extent.width
        let outputScaleY = size.height / extent.height
        var outputImage = self.transformed(by: CGAffineTransform(scaleX: outputScaleX, y: outputScaleY))
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
        )
        return outputImage
    }
    
    public func withAlpha<T: BinaryFloatingPoint>(_ alpha: T) -> CIImage? {
        guard alpha != 1 else { return self }
        
        let filter = CIFilter.colorMatrix()
        filter.inputImage = self
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))

        return filter.outputImage
    }

    public func applyingThreshold(_ threshold: Float) -> CIImage? {
        let filter = CIFilter.colorThreshold()
        filter.inputImage = self
        filter.threshold = threshold
        return filter.outputImage
    }
}

extension CIContext {
    /// Renders an image to a new pixel buffer.
    func render(_ image: CIImage, pixelFormat: OSType) -> CVPixelBuffer? {
        var output: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.extent.width),
            Int(image.extent.height),
            pixelFormat,
            nil,
            &output
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        render(image, to: output, bounds: image.extent, colorSpace: nil)
        return output
    }

    /// Writes the image as a PNG.
    func writePNG(_ image: CIImage, to url: URL) {
        let outputCGImage = createCGImage(image, from: image.extent, format: .BGRA8, colorSpace: nil)!
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("Failed to create an image destination.")
        }
        CGImageDestinationAddImage(destination, outputCGImage, nil)
        CGImageDestinationFinalize(destination)
    }
}
