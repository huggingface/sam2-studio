//
//  SAM2.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import SwiftUI
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine

@MainActor
class SAM2: ObservableObject {
    
    @Published var imageEncodings: sam2_tiny_image_encoderOutput?
    @Published var promptEncodings: sam2_tiny_prompt_encoderOutput?

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

    func getImageEncoding(from url: URL) async throws {
        guard let model = imageEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }

        let inputs = try sam2_small_image_encoderInput(imageAt: url)
        let encoding = try await model.prediction(input: inputs)
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
    
    func getMask(for original_size: CGSize) async throws -> CIImage? {
        guard let model = maskDecoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        if let image_embedding = self.imageEncodings?.image_embedding,
           let feats0 = self.imageEncodings?.feats_s0,
           let feats1 = self.imageEncodings?.feats_s1,
           let sparse_embedding = self.promptEncodings?.sparse_embeddings,
           let dense_embedding = self.promptEncodings?.dense_embeddings {
            let output = try model.prediction(image_embedding: image_embedding, sparse_embedding: sparse_embedding, dense_embedding: dense_embedding, feats_s0: feats0, feats_s1: feats1)

            // Extract only mask 3 to test
            let low_featureMask = MLMultiArray(output.low_res_masksShapedArray[0, 2])
            

            // TODO: optimization
            // Preserve range for upsampling
            var minValue: Double = 9999
            var maxValue: Double = -9999
            for i in 0..<low_featureMask.count {
                let v = low_featureMask[i].doubleValue
                if v > maxValue { maxValue = v }
                if v < minValue { minValue = v }
            }
            let threshold = -minValue / (maxValue - minValue)

            // Resize first, then threshold
            if let maskcgImage = low_featureMask.cgImage(min: minValue, max: maxValue) {
                let ciImage = CIImage(cgImage: maskcgImage, options: [.colorSpace: NSNull()])
                let resizedImage = try resizeImage(ciImage, to: original_size, applyingThreshold: Float(threshold))
                return resizedImage?.maskedToAlpha()?.samTinted()
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
    
    private func resizeImage(_ image: CIImage, to size: CGSize, applyingThreshold threshold: Float = 1) throws -> CIImage? {
        let scale = CGAffineTransform(scaleX: size.width / image.extent.width,
                                      y: size.height / image.extent.height)
        return image.transformed(by: scale).applyingThreshold(threshold)
    }
}

extension CIImage {
    /// This is only appropriate for grayscale mask images (our case). CIColorMatrix can be used more generally.
    func maskedToAlpha() -> CIImage? {
        let filter = CIFilter.maskToAlpha()
        filter.inputImage = self
        return filter.outputImage
    }

    func samTinted() -> CIImage? {
        let filter = CIFilter.colorMatrix()
        filter.rVector = CIVector(x: 30/255, y: 0, z: 0, w: 1)
        filter.gVector = CIVector(x: 0, y: 144/255, z: 0, w: 1)
        filter.bVector = CIVector(x: 0, y: 0, z: 1, w: 1)
        filter.biasVector = CIVector(x: -1, y: -1, z: -1, w: 0)
        filter.inputImage = self
        return filter.outputImage?.cropped(to: self.extent)
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
