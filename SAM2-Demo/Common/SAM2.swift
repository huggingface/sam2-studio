//
//  SAM2.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import AVFoundation
import SwiftUI
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
import UniformTypeIdentifiers

@MainActor
class SAM2: ObservableObject {
    
    var imageEncodings: SAM2_1SmallImageEncoderFLOAT16Output?
    var promptEncodings: SAM2_1SmallPromptEncoderFLOAT16Output?

    @Published private(set) var initializationTime: TimeInterval?
    @Published private(set) var initialized: Bool?

    private var imageEncoderModel: SAM2_1SmallImageEncoderFLOAT16?
    private var promptEncoderModel: SAM2_1SmallPromptEncoderFLOAT16?
    private var maskDecoderModel: SAM2_1SmallMaskDecoderFLOAT16?
    private var memoryEncoderModel: SAM2_1SmallMemoryEncoderFLOAT16?
    private var memoryFusionModel: SAM2_1SmallMemoryFusionFLOAT16?

    var memoryFeatures: MLMultiArray?
    var memoryPositionalEncoding: MLMultiArray?

    @Published var currentFrameIndex: Int = 0
    @Published var isVideoMode: Bool = false
    @Published var videoFrames: [NSImage] = []

    private let maxMemoryFrames = 7 // Default from SAM2
    private let hiddenDim = 256
    private var recentMemoryFeatures: [(Int, (MLMultiArray, MLMultiArray))] = [] // (frameIndex, features)
    private let tempOutputDictPerObj: [String: [String: AnyObject]] = [:]
    private let noMemEmbed: MLMultiArray
    private let noMemPosEnc: MLMultiArray

    // TODO: examine model inputs instead
    var inputSize: CGSize { CGSize(width: 1024, height: 1024) }
    var width: CGFloat { inputSize.width }
    var height: CGFloat { inputSize.height }

    init() {
        var _noMemEmbed =  try! MLMultiArray(shape: [1, 1, NSNumber(value: hiddenDim)], dataType: .float32)
        var _noMemPosEnc = try! MLMultiArray(shape: [1, 1, NSNumber(value: hiddenDim)], dataType: .float32)
        truncNormal(&_noMemEmbed, std: 0.02)
        truncNormal(&_noMemPosEnc, std: 0.02)
        noMemEmbed = _noMemEmbed
        noMemPosEnc = _noMemPosEnc
        Task {
            await loadModels()
        }
    }
    
    private func loadModels() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU
            let (imageEncoder, promptEncoder, maskDecoder, memoryEncoder, memoryFusion) = try await Task.detached(priority: .userInitiated) {
                let imageEncoder = try SAM2_1SmallImageEncoderFLOAT16(configuration: configuration)
                let promptEncoder = try SAM2_1SmallPromptEncoderFLOAT16(configuration: configuration)
                let maskDecoder = try SAM2_1SmallMaskDecoderFLOAT16(configuration: configuration)
                let memoryEncoder = try SAM2_1SmallMemoryEncoderFLOAT16(configuration: configuration)
                let memoryFusion = try SAM2_1SmallMemoryFusionFLOAT16(configuration: configuration)
                return (imageEncoder, promptEncoder, maskDecoder, memoryEncoder, memoryFusion)
            }.value
            
            let endTime = CFAbsoluteTimeGetCurrent()
            self.initializationTime = endTime - startTime
            self.initialized = true

            self.imageEncoderModel = imageEncoder
            self.promptEncoderModel = promptEncoder
            self.maskDecoderModel = maskDecoder
            self.memoryEncoderModel = memoryEncoder
            self.memoryFusionModel = memoryFusion
            print("Initialized models in \(String(format: "%.4f", self.initializationTime!)) seconds")
        } catch {
            print("Failed to initialize models: \(error)")
            self.initializationTime = nil
            self.initialized = false
        }
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

        let inputs = try SAM2_1SmallImageEncoderFLOAT16Input(imageAt: url)
        let encoding = try await model.prediction(input: inputs)
        self.imageEncodings = encoding
    }

    func getPromptEncoding(from allPoints: [SAMPoint]?, with size: CGSize) async throws {
        guard let model = promptEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }

        if let allPoints = allPoints {
            let transformedCoords = try transformCoords(allPoints.map { $0.coordinates }, normalize: false, origHW: size)

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
        } else {
            // Create MLFeatureProvider with the required input format
            let pointsMultiArray = try MLMultiArray(shape: [1, 1, 2], dataType: .float32)
            let labelsMultiArray = try MLMultiArray(shape: [1, 1], dataType: .int32)

            pointsMultiArray[[0, 0, 0] as [NSNumber]] = NSNumber(value: 0)
            pointsMultiArray[[0, 0, 1] as [NSNumber]] = NSNumber(value: 0)
            labelsMultiArray[[0, 0] as [NSNumber]] = NSNumber(value: -1)

            let encoding = try model.prediction(points: pointsMultiArray, labels: labelsMultiArray)
            self.promptEncodings = encoding
        }
    }

    func encodeMemory(pixFeat: MLMultiArray, mask: MLMultiArray) async throws -> (MLMultiArray, MLMultiArray) {
        guard let model = memoryEncoderModel else {
            throw SAM2Error.modelNotLoaded
        }

        let output = try model.prediction(pix_feat: pixFeat, masks: mask)
        return (output.memory_features, output.memory_pos_enc)
    }

    func memoryAttention(
        currFeats: MLMultiArray,
        currPos: MLMultiArray,
        memory: MLMultiArray,
        memoryPos: MLMultiArray,
        numMemoryTokens: MLMultiArray
    ) async throws -> MLMultiArray {
        guard let model = memoryFusionModel else {
            throw SAM2Error.modelNotLoaded
        }

        let output = try model.prediction(
            curr_feats: currFeats,
            curr_pos: currPos,
            memory: memory,
            memory_pos: memoryPos,
            num_memory_tokens: numMemoryTokens
        )

        return output.fused_features
    }

    func bestMask(for output: SAM2_1SmallMaskDecoderFLOAT16Output) -> MLMultiArray {
        if #available(macOS 15.0, *) {
            let scores = output.scoresShapedArray.scalars
            let argmax = scores.firstIndex(of: scores.max() ?? 0) ?? 0
            return MLMultiArray(output.low_res_masksShapedArray[0, argmax])
        } else {
            // Convert scores to float32 for compatibility with macOS < 15,
            // plus ugly loop copy (could do some memcpys)
            let scores = output.scores
            let floatScores = (0..<scores.count).map { scores[$0].floatValue }
            let argmax = floatScores.firstIndex(of: floatScores.max() ?? 0) ?? 0
            let allMasks = output.low_res_masks
            let (h, w) = (allMasks.shape[2], allMasks.shape[3])
            let slice = try! MLMultiArray(shape: [h, w], dataType: allMasks.dataType)
            for i in 0..<h.intValue {
                for j in 0..<w.intValue {
                    let position = [0, argmax, i, j] as [NSNumber]
                    slice[[i as NSNumber, j as NSNumber]] = allMasks[position]
                }
            }
            return slice
        }
    }

    func getMask(imageEncodings: SAM2_1SmallImageEncoderFLOAT16Output, promptEncodings: SAM2_1SmallPromptEncoderFLOAT16Output, for original_size: CGSize) async throws -> (MLMultiArray?, CIImage?) {
        guard let model = maskDecoderModel else {
            throw SAM2Error.modelNotLoaded
        }

        let output = try model.prediction(
            image_embedding: imageEncodings.image_embedding,
            sparse_embedding: promptEncodings.sparse_embeddings,
            dense_embedding: promptEncodings.dense_embeddings,
            feats_s0: imageEncodings.feats_s0,
            feats_s1: imageEncodings.feats_s1
        )

        // Extract best mask and ignore the others
        let lowFeatureMask = bestMask(for: output)

        // TODO: optimization
        // Preserve range for upsampling
        var minValue: Double = 9999
        var maxValue: Double = -9999
        for i in 0..<lowFeatureMask.count {
            let v = lowFeatureMask[i].doubleValue
            if v > maxValue { maxValue = v }
            if v < minValue { minValue = v }
        }
        let threshold = -minValue / (maxValue - minValue)

        // Resize first, then threshold
        if let maskcgImage = lowFeatureMask.cgImage(min: minValue, max: maxValue) {
            let ciImage = CIImage(cgImage: maskcgImage, options: [.colorSpace: NSNull()])
            let resizedImage = try resizeImage(ciImage, to: original_size, applyingThreshold: Float(threshold))
            return (lowFeatureMask, resizedImage?.maskedToAlpha()?.samTinted())
        }

        return (nil, nil)
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

    func loadVideo(from url: URL) async throws {
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access the video file. Security-scoped resource access denied.")
            throw SAM2Error.videoLoadFailed
        }

        defer { url.stopAccessingSecurityScopedResource() }

        // Clear any existing state
        videoFrames.removeAll()
        isVideoMode = true
        currentFrameIndex = 0

        // Create asset reader
        let asset = AVAsset(url: url)
        let track: AVAssetTrack?
        do {
            track = try await asset.loadTracks(withMediaType: .video).first
        } catch {
            print("Failed to load video tracks: \(error)")
            throw SAM2Error.videoLoadFailed
        }
        guard let track else {
            throw SAM2Error.videoLoadFailed
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        // Get video properties
        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let frameCount = Int(CMTimeGetSeconds(duration) * Float64(nominalFrameRate))

        // Use 6 FPS for segmentation like SAM2 demo
        let targetFPS: Float = 6
        let frameStep = Int(round(nominalFrameRate / targetFPS))

        // Load frames
        var frameIndex = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            // Skip frames to achieve target FPS
            if frameIndex % frameStep != 0 {
                frameIndex += 1
                continue
            }

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            // Create CGImage
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                continue
            }

            // Create NSImage and append to frames array
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            videoFrames.append(nsImage)

            frameIndex += 1

            // Update progress
            let progress = Double(frameIndex) / Double(frameCount)
            print("Loading frames: \(Int(progress * 100))%")
        }

        // Check reader status
        if reader.status == .failed {
            throw reader.error ?? SAM2Error.videoLoadFailed
        }

        // Validate we got some frames
        guard !videoFrames.isEmpty else {
            throw SAM2Error.videoLoadFailed
        }

        print("Loaded \(videoFrames.count) frames at \(targetFPS) FPS")
    }

    func encodeMemoryInOutput(with mask: MLMultiArray) async throws {
        guard isVideoMode else { return }

        // 1. Encode current frame and mask into memory features/pos enc
        // Get pixel features directly from current image encoding
        let pix_feat = imageEncodings!.image_embedding

        let maskBinarized = try MLMultiArray(shape: mask.shape, dataType: mask.dataType)
        for i in 0..<mask.count {
            maskBinarized[i] = (mask[i].floatValue > 0 ? 10 : -10)
        }

        let (memFeatures, memPosEnc) = try await encodeMemory(
            pixFeat: pix_feat,
            mask: maskBinarized
        )

        // 2. Store features and pos enc for this frame
        recentMemoryFeatures.append((currentFrameIndex, (memFeatures, memPosEnc)))
        if recentMemoryFeatures.count > maxMemoryFrames {
            recentMemoryFeatures.removeFirst()
        }

        // 3. Concatenate memory features
        // Get shape info from first memory features
        let memShape = memFeatures.shape.map { $0.intValue }
        // In BCHW format:
        let B = memShape[0]
        let C = memShape[1]
        let H = memShape[2]
        let W = memShape[3]
        let M = H * W  // Spatial dimension

        // Get position encoding shape
        let C_pos = memPosEnc.shape[1].intValue

        // Create concatenated memory arrays
        let numMemories = recentMemoryFeatures.count
        let combinedFeatShape = [NSNumber(value: M * numMemories), 1, NSNumber(value: C)]
        let combinedPosShape = [NSNumber(value: M * numMemories), 1, NSNumber(value: C_pos)]

        let combinedFeatures = try MLMultiArray(shape: combinedFeatShape, dataType: .float32)
        let combinedPosEnc = try MLMultiArray(shape: combinedPosShape, dataType: .float32)

        // Copy each frame's memory features and position encoding
        for (i, (_, (frameFeatures, framePosEnc))) in recentMemoryFeatures.enumerated() {
            // Reshape frame features from BCHW to (M,1,C)
            let frameFeatsReshaped = try reshapeToAttentionFormat(
                frameFeatures,
                fromShape: memShape,
                toShape: [M, 1, C]
            )

            // Reshape position encoding from BCHW to (M,1,C_pos)
            let framePosReshaped = try reshapeToAttentionFormat(
                framePosEnc,
                fromShape: [B, C_pos, H, W],
                toShape: [M, 1, C_pos]
            )

            // Copy features into combined array
            for m in 0..<M {
                for c in 0..<C {
                    let fromIndex = [m, 0, c] as [NSNumber]
                    let toIndex = [i*M + m, 0, c] as [NSNumber]
                    combinedFeatures[toIndex] = frameFeatsReshaped[fromIndex]
                }
            }

            // Copy position encodings
            for m in 0..<M {
                for c in 0..<C_pos {
                    let fromIndex = [m, 0, c] as [NSNumber]
                    let toIndex = [i*M + m, 0, c] as [NSNumber]
                    combinedPosEnc[toIndex] = framePosReshaped[fromIndex]
                }
            }
        }

        // Store final concatenated arrays
        memoryFeatures = combinedFeatures
        memoryPositionalEncoding = combinedPosEnc

        // TODO: occlusion handling if self.no_obj_embed_spatial is not None:
    }

    // Tracks state of video processing
    struct TrackingState {
        var framesAlreadyTracked: [Int: Bool] = [:]
        var trackingHasStarted: Bool = false
        var consolidatedFrameIndices: Set<Int> = []
    }

    // Add to class properties
    private var trackingState = TrackingState()
    @Published private(set) var consolidatedOutputs: [Int: (MLMultiArray, CGImage)] = [:]

    func propagateInVideoPreflight() async throws {
        // Mark tracking as started
        trackingState.trackingHasStarted = true

        // Verify we have input prompts that need consolidation
        let hasInputsToConsolidate = !trackingState.consolidatedFrameIndices.isEmpty

        // If there are frames with clicks/prompts to consolidate
        if hasInputsToConsolidate {
            for frameIdx in trackingState.consolidatedFrameIndices {
                // Create consolidated output for frames with prompts
                let (maskMLArray, maskCGImage) = try await getMask(imageEncodings: imageEncodings!, promptEncodings: promptEncodings!, for: videoFrames[frameIdx].size)

                if let maskMLArray = maskMLArray, let maskCGImage = maskCGImage {
                    // Store consolidated output
                    consolidatedOutputs[frameIdx] = (maskMLArray, maskCGImage) as! (MLMultiArray, CGImage)
                }
            }
        }
    }

    func propagateInVideo(startFrameIndex: Int? = nil, maxFramesToTrack: Int? = nil, reverse: Bool = false) async throws {
        // Validate and set up initial state
        guard isVideoMode else { throw SAM2Error.notInVideoMode }
        guard !consolidatedOutputs.isEmpty else {
            throw SAM2Error.noClicksProvided
        }

        // Mark that tracking has started - after this, can't add new objects
        trackingState.trackingHasStarted = true

        let clearNonCondMem = false

        // Determine start, end, and processing order
        let startIdx = startFrameIndex ?? consolidatedOutputs.keys.min() ?? 0
        let maxFrames = maxFramesToTrack ?? videoFrames.count

        let endIdx: Int
        let processingRange: [Int]
        if reverse {
            endIdx = max(startIdx - maxFrames, 0)
            if startIdx > 0 {
                processingRange = Array(stride(from: startIdx, through: endIdx + 1, by: -1))
            } else {
                processingRange = [] // Skip reverse tracking if starting from frame 0
            }
        } else {
            endIdx = min(startIdx + maxFrames, videoFrames.count - 1)
            processingRange = Array(startIdx...endIdx)
        }

        // Process each frame in order
        for frameIdx in processingRange {
            print("Processing frame \(frameIdx) of \(videoFrames.count)")
            var currentMaskMLArray: MLMultiArray!

            if trackingState.consolidatedFrameIndices.contains(frameIdx) {
                // Handle consolidated frames (frames with clicks/mask inputs)
                currentMaskMLArray = consolidatedOutputs[frameIdx]!.0

                if clearNonCondMem {
                    try await clearNonCondMemAroundInput(frameIdx)
                }
            } else {

                let (maskMLArray, maskCGImage) = try await runSingleFrameInference(
                    frameIdx: frameIdx,
                    isInitialFrame: false,
                    pointInputs: nil,
                    reverse: reverse
                )

                if let maskMLArray = maskMLArray, let maskCGImage = maskCGImage {
                    consolidatedOutputs[frameIdx] = (maskMLArray, maskCGImage)
                    currentMaskMLArray = maskMLArray
                }
            }

            // Mark frame as tracked
            trackingState.framesAlreadyTracked[frameIdx] = true
        }
    }

    func clearNonCondMemAroundInput(_ frameIdx: Int) async throws {
        let r = 1 //memoryTemporalStride
        let frameIdxBegin = frameIdx - r * maxMemoryFrames
        let frameIdxEnd = frameIdx + r * maxMemoryFrames

        for t in frameIdxBegin...frameIdxEnd {
            consolidatedOutputs.removeValue(forKey: t)
        }
    }

    private func runSingleFrameInference(
        frameIdx: Int,
        isInitialFrame: Bool,
        pointInputs: [SAMPoint]?,
        reverse: Bool
    ) async throws -> (MLMultiArray?, CGImage?) {

        // Get image encoding for current frame
        try await getImageEncoding(from: videoFrames[frameIdx].pixelBuffer(width: Int(width), height: Int(height))!)

        let pixFeat = try await prepareMemoryConditionedFeatures(isInitialFrame: isInitialFrame)

        let imageEncodings = SAM2_1SmallImageEncoderFLOAT16Output(
            image_embedding: pixFeat,
            vision_feats_s0: imageEncodings!.vision_feats_s0,
            vision_feats_s1: imageEncodings!.vision_feats_s1,
            vision_feats_s2: imageEncodings!.vision_feats_s2,
            feats_s0: imageEncodings!.feats_s0,
            feats_s1: imageEncodings!.feats_s1,
            vision_pos_embeds_s0: imageEncodings!.vision_pos_embeds_s0,
            vision_pos_embeds_s1: imageEncodings!.vision_pos_embeds_s1,
            vision_pos_embeds_s2: imageEncodings!.vision_pos_embeds_s2
        )

        // If we have point inputs, get prompt encoding
        let frameSize = CGSize(width: videoFrames[frameIdx].size.width,
                               height: videoFrames[frameIdx].size.height)
        try await getPromptEncoding(from: pointInputs, with: frameSize)

        // Get predicted mask
        let originalSize = NSSize(
            width: videoFrames[frameIdx].size.width,
            height: videoFrames[frameIdx].size.height
        )
        let (maskMLArray, maskCIImage) = try await getMask(imageEncodings: imageEncodings, promptEncodings: promptEncodings!, for: originalSize)
        guard let maskMLArray, let maskCIImage else { return (nil, nil) }

        let maskResized = try await getOriginalVideoResOutput(maskMLArray)

        // Create segmentation image
        let context = CIContext()
        guard let maskCGImage = context.createCGImage(maskCIImage, from: maskCIImage.extent) else {
            return (nil, nil)
        }

        try await encodeMemoryInOutput(with: maskResized)

        return (maskResized, maskCGImage)
    }

    func getMaskForClick(
        frameIndex: Int,
        points: [SAMPoint]?,
        isInitialFrame: Bool = false
    ) async throws -> CGImage? {
        guard isVideoMode else { throw SAM2Error.notInVideoMode }

        let reverse = trackingState.framesAlreadyTracked[frameIndex] ?? false

        let (maskMLArray, maskCGImage) = try await runSingleFrameInference(
            frameIdx: frameIndex,
            isInitialFrame: isInitialFrame,
            pointInputs: points,
            reverse: reverse
        )

        if let maskMLArray = maskMLArray, let maskCGImage = maskCGImage {
            consolidatedOutputs[frameIndex] = (maskMLArray, maskCGImage)
            trackingState.consolidatedFrameIndices.insert(frameIndex)
        }

        return maskCGImage
    }

    private func prepareMemoryConditionedFeatures(isInitialFrame: Bool) async throws -> MLMultiArray {

        if !isInitialFrame {
            // TODO: this should be more complex - iterating over previous frames
            let H = 64  // Feature map height
            let W = 64  // Feature map width
            let C = hiddenDim  // Hidden dimension (256)
            let HW = H * W

            // 1. Prepare current features tensor by reshaping from BCHW to (HW,B,C)
            let currentFeats = try reshapeToAttentionFormat(
                imageEncodings!.image_embedding,
                fromShape: [1, C, H, W],
                toShape: [HW, 1, C]
            )

            // 2. Get position encoding for current features (reshape from BCHW to HW,B,C)
            let currentPos = try reshapeToAttentionFormat(
                imageEncodings!.vision_pos_embeds_s2,
                fromShape: [1, C, H, W],
                toShape: [HW, 1, C]
            )

            // 3. Perform memory attention
            // Note: memoryFeatures and memoryPositionalEncoding come from encodeMemoryInOutput
            if let memoryFeats = memoryFeatures,
               let memoryPosEnc = memoryPositionalEncoding {

                let numMemoryTokens = try MLMultiArray([Int32(recentMemoryFeatures.count)])

                // Run memory attention between current features and stored memories
                let fusedFeats = try await memoryAttention(
                    currFeats: currentFeats,
                    currPos: currentPos,
                    memory: memoryFeats,
                    memoryPos: memoryPosEnc,
                    numMemoryTokens: numMemoryTokens
                )

                // Reshape fused features back to BCHW format
                return fusedFeats

            } else {
                // If no memories yet, just return the raw image embeddings
                return imageEncodings!.image_embedding
            }
        } else {
            let pixFeatWithMem = imageEncodings!.vision_feats_s2
            let result = try MLMultiArray(shape: [4096, 1, 256], dataType: .float16)

            for i in 0..<4096 {
                for k in 0..<256 {
                    let aValue = pixFeatWithMem[[i, 0, k] as [NSNumber]].floatValue
                    let bValue = noMemEmbed[[0, 0, k] as [NSNumber]].floatValue
                    result[[i, 0, k] as [NSNumber]] = NSNumber(value: aValue + bValue)
                }
            }

            let H = 64
            let W = 64
            let C = hiddenDim
            let HW = H * W

            return try reshapeFromAttentionFormat(
                result,
                fromShape: [HW, 1, C],
                toShape: [1, C, H, W]
            )
        }
    }

    // Helper function to convert CIImage mask to MLMultiArray
    private func maskCIImageToMLArray(_ ciImage: CIImage) throws -> MLMultiArray {
        // Create MLMultiArray with appropriate shape
        let shape = [1, 1, NSNumber(value: Int(ciImage.extent.height)),
                     NSNumber(value: Int(ciImage.extent.width))]
        let array = try MLMultiArray(shape: shape, dataType: .float32)

        // TODO: Convert CIImage pixel data to MLMultiArray values
        // This needs careful implementation to preserve mask values

        return array
    }

    // Helper function to reshape tensors between BCHW and attention formats
    private func reshapeToAttentionFormat(_ array: MLMultiArray, fromShape: [Int], toShape: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: toShape.map { NSNumber(value: $0) }, dataType: array.dataType)

        // Input is BCHW format
        let B = fromShape[0]
        let C = fromShape[1]  // Changed: channels is second dimension
        let H = fromShape[2]
        let W = fromShape[3]
        let HW = H * W

        // Reshape to (HW,B,C) format
        for h in 0..<H {
            for w in 0..<W {
                for c in 0..<C {
                    let fromIndex = [0, c, h, w] as [NSNumber]  // BCHW
                    let toIndex = [h * W + w, 0, c] as [NSNumber]  // HW,B,C
                    result[toIndex] = array[fromIndex]
                }
            }
        }

        return result
    }

    private func reshapeFromAttentionFormat(_ array: MLMultiArray, fromShape: [Int], toShape: [Int]) throws -> MLMultiArray {
        let result = try MLMultiArray(shape: toShape.map { NSNumber(value: $0) }, dataType: array.dataType)

        // Input is (HW,B,C)
        let HW = fromShape[0]
        let B = fromShape[1]
        let C = fromShape[2]

        // Output should be BCHW
        let H = Int(sqrt(Double(HW)))  // Changed: calculate H from HW
        let W = H  // Assuming square feature maps

        // Reshape from (HW,B,C) back to (B,C,H,W)
        for hw in 0..<HW {
            let h = hw / W
            let w = hw % W
            for c in 0..<C {
                let fromIndex = [hw, 0, c] as [NSNumber]  // HW,B,C
                let toIndex = [0, c, h, w] as [NSNumber]  // BCHW
                result[toIndex] = array[fromIndex]
            }
        }

        return result
    }

    func getOriginalVideoResOutput(_ lowResMasks: MLMultiArray) async throws -> MLMultiArray {
        guard isVideoMode else { throw SAM2Error.notInVideoMode }

        let videoSize = CGSize(width: width, height: height)

        // Resize to video resolution
        let videoResMasks = try lowResMasks.resizedMaskArray(toSize: videoSize)

        // Apply non-overlapping constraints if needed
        let finalMasks = try videoResMasks.applyNonOverlappingConstraints()

        return finalMasks
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
    case notInVideoMode
    case noClicksProvided
    case videoLoadFailed
    case invalidDimensions
}

@discardableResult func writeCGImage(_ image: CGImage, to destinationURL: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}
