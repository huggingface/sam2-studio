import ArgumentParser
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers
import Combine

let context = CIContext()

enum PointType: Int, ExpressibleByArgument {
    case background = 0
    case foreground = 1

    var asCategory: SAMCategory {
        switch self {
            case .background:
                return SAMCategory.background
            case .foreground:
                return SAMCategory.foreground
        }
    }
}

@main
struct MainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sam2-cli",
        abstract: "Perform segmentation using the SAM v2 model."
    )

    @Option(name: .shortAndLong, help: "The input image file.")
    var input: String

    // TODO: multiple points
    @Option(name: .shortAndLong, help: "Input coordinates in format 'x,y'. Coordinates are relative to the input image size.")
    var point: CGPoint

    @Option(name: .shortAndLong, help: "Point type.")
    var type: PointType

    @Option(name: .shortAndLong, help: "The output PNG image file, showing the segmentation map overlaid on top of the original image.")
    var output: String

    @Option(name: [.long, .customShort("k")], help: "The output file name for the segmentation mask.")
    var mask: String? = nil

    @Option(name: .shortAndLong, help: "The output file name for the unresized (but thresholded) mask.")
    var rawMask: String? = nil

    @MainActor
    mutating func run() async throws {
        // TODO: specify directory with loadable .mlpackages instead
        let sam = try await SAM2.load()
        print("Models loaded in: \(String(describing: sam.initializationTime))")
        let targetSize = sam.inputSize

        // Load the input image
        guard let inputImage = CIImage(contentsOf: URL(filePath: input)) else {
            print("Failed to load image.")
            throw ExitCode(EXIT_FAILURE)
        }
        print("Original image size \(inputImage.extent)")

        // Resize the image to match the model's expected input
        let resizedImage = inputImage.resized(to: targetSize)

        // Convert to a pixel buffer
        guard let pixelBuffer = context.render(resizedImage, pixelFormat: kCVPixelFormatType_32ARGB) else {
            print("Failed to create pixel buffer for input image.")
            throw ExitCode(EXIT_FAILURE)
        }

        // Execute the model
        let clock = ContinuousClock()
        let start = clock.now
        try await sam.getImageEncoding(from: pixelBuffer)
        let duration = clock.now - start
        print("Image encoding took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])))")

        let startMask = clock.now
        let pointSequence = [SAMPoint(coordinates:point, category:SAMCategory.foreground)]
        try await sam.getPromptEncoding(from: pointSequence, with: inputImage.extent.size)
        guard let cgImageMask = try await sam.getMask(for: inputImage.extent.size) else {
            throw ExitCode(EXIT_FAILURE)
        }
        let maskDuration = clock.now - startMask
        print("Prompt encoding and mask generation took \(maskDuration.formatted(.units(allowed: [.seconds, .milliseconds])))")

        let maskImage = CIImage(cgImage: cgImageMask)

        // Write masks
        if let mask = mask {
            context.writePNG(maskImage, to: URL(filePath: mask))
        }
        if let rawMask = rawMask, let cgMask = sam.thresholdedMask {
            context.writePNG(CIImage(cgImage: cgMask), to: URL(filePath: rawMask))
        }

        // Overlay over original and save
        guard let outputImage = maskImage.withAlpha(0.5)?.composited(over: inputImage) else {
            print("Failed to blend mask.")
            throw ExitCode(EXIT_FAILURE)
        }
        context.writePNG(outputImage, to: URL(filePath: output))
    }
}

extension CGPoint: ExpressibleByArgument {
    public init?(argument: String) {
        let components = argument.split(separator: ",").map(String.init)

        guard components.count == 2,
              let x = Double(components[0]),
              let y = Double(components[1]) else {
            return nil
        }

        self.init(x: x, y: y)
    }
}
