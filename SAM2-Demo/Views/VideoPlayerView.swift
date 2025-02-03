//
//  VideoPlayerView.swift
//  SAM2-Demo
//
//  Created by Martin Stachon on 11.01.2025.
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @ObservedObject var sam2: SAM2
    @Binding var imageSize: NSSize
    @Binding var originalSize: NSSize?
    @Binding var selectedPoints: [SAMPoint]
    @Binding var boundingBoxes: [SAMBox]
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var selectedTool: SAMTool?
    @Binding var selectedCategory: SAMCategory?
    @Binding var currentBox: SAMBox?

    var body: some View {
        VStack {
            // Video display
            if !sam2.videoFrames.isEmpty {
                ImageView(
                    image: sam2.videoFrames[sam2.currentFrameIndex],
                    currentScale: .constant(1.0),
                    selectedTool: $selectedTool,
                    selectedCategory: $selectedCategory,
                    selectedPoints: $selectedPoints,
                    boundingBoxes: $boundingBoxes,
                    currentBox: $currentBox,
                    segmentationImages: $segmentationImages,
                    currentSegmentation: currentSegmentation(),
                    imageSize: $imageSize,
                    originalSize: $originalSize,
                    sam2: sam2
                )
            }

            // Timeline controls
            HStack {
                Button(action: previousFrame) {
                    Image(systemName: "backward.fill")
                }

                if !sam2.videoFrames.isEmpty {
                    Slider(
                        value: .init(
                            get: { Double(sam2.currentFrameIndex) },
                            set: { seek(to: Int($0)) }
                        ),
                        in: 0...Double(sam2.videoFrames.count - 1)
                    )
                }

                Button(action: nextFrame) {
                    Image(systemName: "forward.fill")
                }
            }
            .padding()
        }
    }

    func currentSegmentation() -> SAMSegmentation? {
        guard let output = sam2.consolidatedOutputs[sam2.currentFrameIndex] else {
            return nil
        }
        return SAMSegmentation(image: CIImage(cgImage: output.1), tintColor: SAMSegmentation.defaultColor)
    }

    private func seek(to frame: Int) {
        sam2.currentFrameIndex = frame
    }

    private func nextFrame() {
        let nextIndex = min(sam2.currentFrameIndex + 1, sam2.videoFrames.count - 1)
        seek(to: nextIndex)
    }

    private func previousFrame() {
        let prevIndex = max(sam2.currentFrameIndex - 1, 0)
        seek(to: prevIndex)
    }
}
