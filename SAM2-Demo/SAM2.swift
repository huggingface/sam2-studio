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
            
            
            // Convert low_featureMask from float16 to float32 and threshold
            let float32Mask = try! MLMultiArray(shape: low_featureMask.shape, dataType: .float32)
            for i in 0..<low_featureMask.count {
                float32Mask[i] = low_featureMask[i].floatValue > 0.0 ? 1.0 : 0.0
            }
            
            // Save mask.low_res_masks
//            if let image = convertMultiArrayToImage(multiArray: float32Mask) {
//                let desktopURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mask.png")
//                if image.pngWrite(to: desktopURL, options: .atomic) {
//                    print("File saved")
//                }
//            } else {
//                print("Failed to convert MultiArray to image")
//            }
            if let maskcgImage = float32Mask.cgImage(min: 0, max: 1, axes: (1, 2, 3)) {
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



// Debug

func convertMultiArrayToImage(multiArray: MLMultiArray, with originalSize: CGSize) -> NSImage? {
    guard multiArray.shape.count == 4,
          multiArray.shape[0] == 1,
          multiArray.shape[1] == 3,
          multiArray.shape[2] == 256,
          multiArray.shape[3] == 256 else {
        print("Invalid multiArray shape")
        return nil
    }

    let width = Int(originalSize.width)
    let height = Int(originalSize.height)
    
    var pixelBuffer = [UInt8](repeating: 0, count: width * height * 4)
    
    // Find min and max values for normalization
    var minValue: Float = Float.infinity
    var maxValue: Float = -Float.infinity
    
    for i in 0..<multiArray.count {
        let value = Float(multiArray[i].floatValue)
        minValue = min(minValue, value)
        maxValue = max(maxValue, value)
    }
    print(maxValue, minValue)
    // Function to normalize values
    func normalize(_ value: Float) -> UInt8 {
        let normalized = (value - minValue) / (maxValue - minValue)
        return UInt8(max(0, min(255, normalized * 255)))
    }
    
    for y in 0..<height {
        for x in 0..<width {
            let redIndex = y * width + x
            let greenIndex = width * height + y * width + x
            let blueIndex = 2 * width * height + y * width + x
            
            let red = Float(multiArray[redIndex].floatValue)
            let green = Float(multiArray[greenIndex].floatValue)
            let blue = Float(multiArray[blueIndex].floatValue)
            
            let pixelIndex = (y * width + x) * 4
            pixelBuffer[pixelIndex] = normalize(red)
            pixelBuffer[pixelIndex + 1] = normalize(green)
            pixelBuffer[pixelIndex + 2] = normalize(blue)
            pixelBuffer[pixelIndex + 3] = 255 // Alpha channel
        }
    }
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    guard let provider = CGDataProvider(data: Data(pixelBuffer) as CFData) else { return nil }
    guard let cgImage = CGImage(width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bitsPerPixel: 32,
                                bytesPerRow: width * 4,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo,
                                provider: provider,
                                decode: nil,
                                shouldInterpolate: true,
                                intent: .defaultIntent) else { return nil }
    
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
}

extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation, let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmapImage.representation(using: .png, properties: [:])
    }
    func pngWrite(to url: URL, options: Data.WritingOptions = .atomic) -> Bool {
        do {
            try pngData?.write(to: url, options: options)
            return true
        } catch {
            print(error)
            return false
        }
    }
}
