import ArgumentParser
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers
import Combine

let context = CIContext(options: [.outputColorSpace: NSNull()])

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
    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "List of input coordinates in format 'x,y'. Coordinates are relative to the input image size. Separate multiple entries with spaces, but don't use spaces between the coordinates.")
    var points: [CGPoint]

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Point types that correspond to the input points. Use as many as points, 0 for background and 1 for foreground.")
    var types: [PointType]

    @Option(name: .shortAndLong, help: "The output PNG image file, showing the segmentation map overlaid on top of the original image.")
    var output: String

    @Option(name: [.long, .customShort("k")], help: "The output file name for the segmentation mask.")
    var mask: String? = nil

    @MainActor
    mutating func run() async throws {
        // TODO: specify directory with loadable .mlpackages instead
        let sam = try await SAM2.load()
        print("Models loaded in: \(String(describing: sam.initializationTime))")
        let targetSize = sam.inputSize

        // Load the input image
        guard let inputImage = CIImage(contentsOf: URL(filePath: input), options: [.colorSpace: NSNull()]) else {
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
        let pointSequence = zip(points, types).map { point, type in
            SAMPoint(coordinates:point, category:type.asCategory)
        }
        try await sam.getPromptEncoding(from: pointSequence, with: inputImage.extent.size)
        guard let maskImage = try await sam.getMask(for: inputImage.extent.size) else {
            throw ExitCode(EXIT_FAILURE)
        }
        let maskDuration = clock.now - startMask
        print("Prompt encoding and mask generation took \(maskDuration.formatted(.units(allowed: [.seconds, .milliseconds])))")

        // Write masks
        if let mask = mask {
            context.writePNG(maskImage, to: URL(filePath: mask))
        }

        // Overlay over original and save
        guard let outputImage = maskImage.withAlpha(0.6)?.composited(over: inputImage) else {
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
