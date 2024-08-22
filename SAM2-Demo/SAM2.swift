//
//  SAM2.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import SwiftUI
import CoreML
import CoreImage

@MainActor
class SAM2: ObservableObject {
    
    @Published var imageEncodings: sam2_tiny_image_encoderOutput?
    @Published var promptEncodings: sam2_tiny_prompt_encoderOutput?
    @Published var maskDecoding: sam2_tiny_mask_decoderOutput?
    
    @Published private(set) var initializationTime: TimeInterval?
    
    private var imageEncoderModel: sam2_tiny_image_encoder?
    private var promptEncoderModel: sam2_tiny_prompt_encoder?
    private var maskDecoderModel: sam2_tiny_mask_decoder?
    
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
            
            self.imageEncoderModel = imageEncoder
            self.promptEncoderModel = promptEncoder
            self.maskDecoderModel = maskDecoder
            print("Initialized models in \(String(format: "%.4f", self.initializationTime!)) seconds")
        } catch {
            print("Failed to initialize models: \(error)")
            self.initializationTime = nil
        }
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

            for i in 0..<low_featureMask.count {
                float32Mask[i] = low_featureMask[i].floatValue > 0.0 ? 1.0 : 0.0
            }
            print(float32Mask.shape)
            let desktopURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("\(UUID().uuidString).png")
            if let maskcgImage = float32Mask.cgImage(min: 0, max: 1, axes: (1, 2, 3)) {
                writeCGImage(maskcgImage, to: desktopURL)
                let resizedImage = try resizeCGImage(maskcgImage, to: original_size)
                return resizedImage
            } else {
                return nil
            }
        }
        return nil
    }

    private func transformCoords(_ coords: [CGPoint], normalize: Bool = false, origHW: CGSize) throws -> [CGPoint] {
        guard normalize else {
            return coords.map { CGPoint(x: $0.x * 1024, y: $0.y * 1024) } // Don't hardcode resolution
        }
        
        let w = origHW.width
        let h = origHW.height
        
        return coords.map { coord in
            let normalizedX = coord.x / w
            let normalizedY = coord.y / h
            return CGPoint(x: normalizedX * 1024, y: normalizedY * 1024)
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
