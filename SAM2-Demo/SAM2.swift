//
//  SAM2.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import SwiftUI
import CoreML

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
    
    func getPromptEncoding(from allPoints: [SAMPoint]) async throws {
        guard let model = promptEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        // Create MLFeatureProvider with the required input format
        let pointsMultiArray = try MLMultiArray(shape: [1, NSNumber(value: allPoints.count), 2], dataType: .float16)
        let labelsMultiArray = try MLMultiArray(shape: [1, NSNumber(value: allPoints.count)], dataType: .float16)
        
        // TODO: check types and speed
        for (index, point) in allPoints.enumerated() {
            pointsMultiArray[[0, NSNumber(value: index), 0] as [NSNumber]] = NSNumber(value: point.coordinates.x)
            pointsMultiArray[[0, NSNumber(value: index), 1] as [NSNumber]] = NSNumber(value: point.coordinates.y)
            labelsMultiArray[[0, NSNumber(value: index)] as [NSNumber]] = NSNumber(value: point.category.type.rawValue)
        }
        
        let encoding = try model.prediction(points: pointsMultiArray, labels: labelsMultiArray)
        self.promptEncodings = encoding
    }
    
    func getMask() async throws -> CGImage? {
        guard let model = maskDecoderModel else {
            throw SAM2Error.modelNotLoaded
        }
        
        if let image_embedding = self.imageEncodings?.image_embedding,
        let feats0 = self.imageEncodings?.feats_s0,
        let feats1 = self.imageEncodings?.feats_s1,
        let sparse_embedding = self.promptEncodings?.sparse_embeddings,
           let dense_embedding = self.promptEncodings?.dense_embeddings {
            let mask = try model.prediction(image_embedding: image_embedding, sparse_embedding: sparse_embedding, dense_embedding: dense_embedding, feats_s0: feats0, feats_s1: feats1)
            let maskcgImage = mask.low_res_masks.cgImage(min: -1, max: 1, axes: (1, 2, 3))
            return maskcgImage
        }
        return nil
    }
}

enum SAM2Error: Error {
    case modelNotLoaded
    case pixelBufferCreationFailed
}
