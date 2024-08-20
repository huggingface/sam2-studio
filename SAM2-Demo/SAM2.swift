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
    @Published var imageEncoding: sam2_tiny_image_encoderOutput?
    @Published private(set) var isModelLoaded = false
    @Published private(set) var initializationTime: TimeInterval?
    private var imageEncoderModel: sam2_tiny_image_encoder?

    init() {
        Task {
            await loadModel()
        }
    }

    private func loadModel() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            let model = try await Task.detached(priority: .userInitiated) {
                try sam2_tiny_image_encoder(configuration: configuration)
            }.value
            
            let endTime = CFAbsoluteTimeGetCurrent()
            self.initializationTime = endTime - startTime
            
            self.imageEncoderModel = model
            self.isModelLoaded = true
            print("Initialized model in \(String(format: "%.4f", self.initializationTime!)) seconds")
        } catch {
            print("Failed to initialize models: \(error)")
            self.isModelLoaded = false
            self.initializationTime = nil
        }
    }
}

enum SAM2Error: Error {
    case modelNotLoaded
    case pixelBufferCreationFailed
}
