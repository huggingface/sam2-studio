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
    
    @State private var viewportSize: CGSize = .zero
    @State private var error: Error?

    let zoomIncrement: CGFloat = 0.1
    let maxZoom: CGFloat = 5.0
    let minZoom: CGFloat = 0.5
    
    var pointSequence: [SAMPoint] {
        boundingBoxes.flatMap { $0.points() } + selectedPoints
    }

    var body: some View {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(currentScale)
                .frame(maxWidth: 500, maxHeight: 500)
                .onAppear {
                    NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { (event) -> NSEvent? in
                        self.handleKeyEvent(event)
                        return event
                    }
                }
                .onTapGesture(coordinateSpace: .local) { handleTap(at: $0) }
                .gesture(boundingBoxGesture)
                .onHover { changeCursorAppearance(is: $0) }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
                })
                .onPreferenceChange(SizePreferenceKey.self) { size in
                    viewportSize = size
                    imageSize = size
                }
                .overlay {
                    PointsOverlay(selectedPoints: $selectedPoints, currentScale: $currentScale, imageSize: $imageSize, selectedTool: $selectedTool)
                    BoundingBoxesOverlay(boundingBoxes: boundingBoxes, currentScale: $currentScale, imageSize: $imageSize, currentBox: currentBox)
                    
                    if !segmentationImages.isEmpty {
                        ForEach($segmentationImages, id: \.id) { segmentationImage in
                            SegmentationOverlay(segmentationImage: segmentationImage, currentScale: $currentScale, imageSize: imageSize)
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
                
                let endPoint = SAMPoint(coordinates: value.location, imageSize: imageSize, currentScale: currentScale, category: selectedCategory!)
                
                if currentBox == nil {
                    let startPoint = SAMPoint(coordinates: value.startLocation, imageSize: imageSize, currentScale: currentScale, category: selectedCategory!)
                    currentBox = SAMBox(startPoint: startPoint, endPoint: endPoint, category: selectedCategory!)
                } else {
                    currentBox?.endPoint = endPoint
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
        self.selectedPoints.append(SAMPoint(coordinates: coordinates, imageSize: imageSize, currentScale: currentScale, category: selectedCategory!))
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
        case [.command]:
            switch event.keyCode {
            case 24: // Command + '+'
                zoomIn()
            case 27: // Command + '-'
                zoomOut()
            case 29: // Command + '0'
                resetZoom()
            default:
                break
            }
        default:
            break
        }
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.05)) {
            currentScale = min(currentScale + zoomIncrement, maxZoom)
        }
    }

    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.05)) {
            currentScale = max(currentScale - zoomIncrement, minZoom)
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.05)) {
            currentScale = 1.0
        }
    }
    
    private func performForwardPass() {
        Task {
            do {
                try await sam2.getPromptEncoding(from: pointSequence, with: imageSize)
                let cgImageMask = try await sam2.getMask(for: originalSize ?? .zero)
                if let cgImageMask {
                    DispatchQueue.main.async {
                        let segmentationNumber = segmentationImages.count
                        let segmentationOverlay = SAMSegmentation(image: cgImageMask, title: "Untitled \(segmentationNumber + 1)")
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

