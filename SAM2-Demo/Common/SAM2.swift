//
//  SAM2.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import SwiftUI
import CoreML
import CoreImage
import Combine

@MainActor
class SAM2: ObservableObject {
    
    @Published var imageEncodings: sam2_tiny_image_encoderOutput?
    @Published var promptEncodings: sam2_tiny_prompt_encoderOutput?
    @Published var thresholdedMask: CGImage?

    @Published private(set) var initializationTime: TimeInterval?
    @Published private(set) var initialized: Bool?

    private var imageEncoderModel: sam2_tiny_image_encoder?
    private var promptEncoderModel: sam2_tiny_prompt_encoder?
    private var maskDecoderModel: sam2_tiny_mask_decoder?

    // TODO: examine model inputs instead
    var inputSize: CGSize { CGSize(width: 1024, height: 1024) }
    var width: CGFloat { inputSize.width }
    var height: CGFloat { inputSize.height }

    init() {
        Task {
            await loadModels()
        }
    }
    
    private func loadModels() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            let (imageEncoder, promptEncoder, maskDecoder) = try await Task.detached(priority: .userInitiated) {
                let imageEncoder = try sam2_tiny_image_encoder(configuration: configuration)
                let promptEncoder = try sam2_tiny_prompt_encoder(configuration: configuration)
                let maskDecoder = try sam2_tiny_mask_decoder(configuration: configuration)
                return (imageEncoder, promptEncoder, maskDecoder)
            }.value
            
            let endTime = CFAbsoluteTimeGetCurrent()
            self.initializationTime = endTime - startTime
            self.initialized = true

            self.imageEncoderModel = imageEncoder
            self.promptEncoderModel = promptEncoder
            self.maskDecoderModel = maskDecoder
            print("Initialized models in \(String(format: "%.4f", self.initializationTime!)) seconds")
        } catch {
            print("Failed to initialize models: \(error)")
            self.initializationTime = nil
            self.initialized = false
        }
    }

    // Convenience for use in the CLI
    private var modelLoading: AnyCancellable?
    func ensureModelsAreLoaded() async throws -> SAM2 {
        let _ = try await withCheckedThrowingContinuation { continuation in
            modelLoading = self.$initialized.sink { newValue in
                if let initialized = newValue {
                    if initialized {
                        continuation.resume(returning: self)
                    } else {
                        continuation.resume(throwing: SAM2Error.modelNotLoaded)
                    }
                }
            }
        }
        return self
    }

    static func load() async throws -> SAM2 {
        try await SAM2().ensureModelsAreLoaded()
    }

    func getImageEncoding(from pixelBuffer: CVPixelBuffer) async throws {
        guard let model = imageEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        let encoding = try model.prediction(image: pixelBuffer)
        self.imageEncodings = encoding
    }
    
    func getPromptEncoding(from allPoints: [SAMPoint], with size: CGSize) async throws {
        guard let model = promptEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        let transformedCoords = try transformCoords(allPoints.map { $0.coordinates }, normalize: true, origHW: size)
        
        // Create MLFeatureProvider with the required input format
        let pointsMultiArray = try MLMultiArray(shape: [1, NSNumber(value: allPoints.count), 2], dataType: .float32)
        let labelsMultiArray = try MLMultiArray(shape: [1, NSNumber(value: allPoints.count)], dataType: .int32)
        
        for (index, point) in transformedCoords.enumerated() {
            pointsMultiArray[[0, index, 0] as [NSNumber]] = NSNumber(value: Float(point.x))
            pointsMultiArray[[0, index, 1] as [NSNumber]] = NSNumber(value: Float(point.y))
            labelsMultiArray[[0, index] as [NSNumber]] = NSNumber(value: allPoints[index].category.type.rawValue)
        }
        
        let encoding = try model.prediction(points: pointsMultiArray, labels: labelsMultiArray)
        self.promptEncodings = encoding
    }
    
    func getMask(for original_size: CGSize) async throws -> CGImage? {
        guard let model = maskDecoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        if let image_embedding = self.imageEncodings?.image_embedding,
           let feats0 = self.imageEncodings?.feats_s0,
           let feats1 = self.imageEncodings?.feats_s1,
           let sparse_embedding = self.promptEncodings?.sparse_embeddings,
           let dense_embedding = self.promptEncodings?.dense_embeddings {
            let output = try model.prediction(image_embedding: image_embedding, sparse_embedding: sparse_embedding, dense_embedding: dense_embedding, feats_s0: feats0, feats_s1: feats1)
            let low_featureMask = output.low_res_masks
            
            
            // Cast low_featureMask from float16 to float32 and threshold
            let float32Mask = try! MLMultiArray(shape: low_featureMask.shape, dataType: .float32)

            // TODO: optimization (threshold, resizing)
            for i in 0..<low_featureMask.count {
                float32Mask[i] = low_featureMask[i].floatValue > 0.0 ? 1.0 : 0.0
            }
            if let maskcgImage = float32Mask.cgImage(min: 0, max: 1, axes: (1, 2, 3)) {
                self.thresholdedMask = maskcgImage
                let resizedImage = try resizeCGImage(maskcgImage, to: original_size)
                if let transparentImage = makeBlackPixelsTransparent(in: resizedImage) {
                    return transparentImage
                }
                return resizedImage
            }
        }
        return nil
    }

    private func transformCoords(_ coords: [CGPoint], normalize: Bool = false, origHW: CGSize) throws -> [CGPoint] {
        guard normalize else {
            return coords.map { CGPoint(x: $0.x * width, y: $0.y * height) }
        }
        
        let w = origHW.width
        let h = origHW.height
        
        return coords.map { coord in
            let normalizedX = coord.x / w
            let normalizedY = coord.y / h
            return CGPoint(x: normalizedX * width, y: normalizedY * height)
        }
    }
    
    private func resizeCGImage(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)
        let scale = CGAffineTransform(scaleX: size.width / CGFloat(image.width),
                                      y: size.height / CGFloat(image.height))
        let scaledImage = ciImage.transformed(by: scale)

        let context = CIContext(options: nil)
        guard let resizedImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw SAM2Error.imageResizingFailed
        }

        return resizedImage
    }
    
    func makeBlackPixelsTransparent(in image: CGImage) -> CGImage? {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return nil
        }
        
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bitsPerComponent = image.bitsPerComponent
        let bitsPerPixel = image.bitsPerPixel
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let pixelData = context.data else {
            return nil
        }
        
        let pixelBuffer = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * 4)
                
                let red = pixelBuffer[offset]
                let green = pixelBuffer[offset + 1]
                let blue = pixelBuffer[offset + 2]
                
                if red == 0 && green == 0 && blue == 0 {
                    pixelBuffer[offset + 3] = 0 // Set alpha to 0 for black pixels
                }
            }
        }
        
        return context.makeImage()
    }
}

enum SAM2Error: Error {
    case modelNotLoaded
    case pixelBufferCreationFailed
    case imageResizingFailed
}

@discardableResult func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, kUTTypePNG, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}
