//
//  ImageView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct ImageView: View {
    let image: NSImage
    @Binding var currentScale: CGFloat
    @Binding var selectedTool: SAMTool?
    @Binding var selectedCategory: SAMCategory?
    @Binding var selectedPoints: [SAMPoint]
    @Binding var boundingBoxes: [SAMBox]
    @Binding var currentBox: SAMBox?
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var imageSize: CGSize
    @Binding var originalSize: NSSize?
    @ObservedObject var sam2: SAM2
    @State private var error: Error?
    
    var pointSequence: [SAMPoint] {
        boundingBoxes.flatMap { $0.points } + selectedPoints
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(currentScale)
            .frame(maxWidth: 500, maxHeight: 500)
            .onTapGesture(coordinateSpace: .local) { handleTap(at: $0) }
            .gesture(boundingBoxGesture)
            .onHover { changeCursorAppearance(is: $0) }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
            })
            .onPreferenceChange(SizePreferenceKey.self) { imageSize = $0 }
            .overlay {
                PointsOverlay(selectedPoints: $selectedPoints, selectedTool: $selectedTool)
                BoundingBoxesOverlay(boundingBoxes: boundingBoxes, currentBox: currentBox)
                
                if !segmentationImages.isEmpty {
                    ForEach($segmentationImages, id: \.id) { segmentationImage in
                        SegmentationOverlay(segmentationImage: segmentationImage, imageSize: imageSize)
                    }
                }
                
               
            }
    }
    
    private func changeCursorAppearance(is inside: Bool) {
        if inside {
            if selectedTool == pointTool {
                NSCursor.pointingHand.push()
            } else if selectedTool == boundingBoxTool {
                NSCursor.crosshair.push()
            }
        } else {
            NSCursor.pop()
        }
    }
    
    private var boundingBoxGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard selectedTool == boundingBoxTool else { return }
                
                if currentBox == nil {
                    currentBox = SAMBox(startPoint: value.startLocation, endPoint: value.location, category: selectedCategory!)
                } else {
                    currentBox?.endPoint = value.location
                }
            }
            .onEnded { value in
                guard selectedTool == boundingBoxTool else { return }
                
                if let box = currentBox {
                    boundingBoxes.append(box)
                    currentBox = nil
                    performForwardPass()
                }
            }
    }
    
    private func handleTap(at location: CGPoint) {
        if selectedTool == pointTool {
            placePoint(at: location)
            performForwardPass()
        }
    }
    
    private func placePoint(at coordinates: CGPoint) {
        let samPoint = SAMPoint(coordinates: coordinates, category: selectedCategory!)
        self.selectedPoints.append(samPoint)
    }
    
    private func performForwardPass() {
        Task {
            do {
                try await sam2.getPromptEncoding(from: pointSequence, with: imageSize)
                if let mask = try await sam2.getMask(for: originalSize ?? .zero) {
                    DispatchQueue.main.async {
                        let segmentationNumber = segmentationImages.count
                        let segmentationOverlay = SAMSegmentation(image: mask, title: "Untitled \(segmentationNumber + 1)")
                        self.segmentationImages.append(segmentationOverlay)
                    }
                }
            } catch {
                self.error = error
            }
        }
    }
}

#Preview {
    ContentView()
}

