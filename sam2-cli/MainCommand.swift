import ArgumentParser
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers
import Combine
import AVFoundation

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
    var input: String?

    @Option(name: .shortAndLong, help: "The input video file.")
    var video: String?

    @Option(name: .shortAndLong, help: "The text prompt for segmentation.")
    var textPrompt: String?

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
        let sam = try await SAM2.load()
        print("Models loaded in: \(String(describing: sam.initializationTime))")

        if let input = input {
            try await processImage(input, with: sam)
        } else if let video = video, let textPrompt = textPrompt {
            try await processVideo(video, with: sam, textPrompt: textPrompt)
        } else {
            print("Please provide either an image input or a video input with a text prompt.")
            throw ExitCode(EXIT_FAILURE)
        }
    }

    private func processImage(_ input: String, with sam: SAM2) async throws {
        let targetSize = sam.inputSize

        guard let inputImage = CIImage(contentsOf: URL(filePath: input), options: [.colorSpace: NSNull()]) else {
            print("Failed to load image.")
            throw ExitCode(EXIT_FAILURE)
        }
        print("Original image size \(inputImage.extent)")

        let resizedImage = inputImage.resized(to: targetSize)

        guard let pixelBuffer = context.render(resizedImage, pixelFormat: kCVPixelFormatType_32ARGB) else {
            print("Failed to create pixel buffer for input image.")
            throw ExitCode(EXIT_FAILURE)
        }

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

        if let mask = mask {
            context.writePNG(maskImage, to: URL(filePath: mask))
        }

        guard let outputImage = maskImage.withAlpha(0.6)?.composited(over: inputImage) else {
            print("Failed to blend mask.")
            throw ExitCode(EXIT_FAILURE)
        }
        context.writePNG(outputImage, to: URL(filePath: output))
    }

    private func processVideo(_ video: String, with sam: SAM2, textPrompt: String) async throws {
        let videoURL = URL(filePath: video)
        let asset = AVAsset(url: videoURL)
        let reader = try AVAssetReader(asset: asset)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("Failed to load video track.")
            throw ExitCode(EXIT_FAILURE)
        }

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
        ])
        reader.add(readerOutput)
        reader.startReading()

        var frameCount = 0
        while let sampleBuffer = readerOutput.copyNextSampleBuffer(), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            frameCount += 1
            try await sam.getVideoEncoding(from: pixelBuffer)
            try await sam.getTextPromptEncoding(from: textPrompt)
            guard let maskImage = try await sam.getMask(for: videoTrack.naturalSize) else {
                throw ExitCode(EXIT_FAILURE)
            }

            let outputURL = URL(filePath: "\(output)_frame_\(frameCount).png")
            context.writePNG(maskImage, to: outputURL)
        }

        print("Processed \(frameCount) frames.")
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
