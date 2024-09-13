//
//  SubtoolbarView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct SubToolbar: View {
    @Binding var selectedPoints: [SAMPoint]
    @Binding var boundingBoxes: [SAMBox]
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var currentSegmentation: SAMSegmentation?

    var body: some View {
        if selectedPoints.count > 0 || boundingBoxes.count > 0 {
            ZStack {
                Rectangle()
                    .fill(.regularMaterial)
                    .frame(height: 30)
                
                HStack {
                    Spacer()
                    Button("Undo", action: undo)
                        .padding(.trailing, 5)
                        .disabled(selectedPoints.isEmpty && boundingBoxes.isEmpty)
                    Button("Reset", action: resetAll)
                        .padding(.trailing, 5)
                        .disabled(selectedPoints.isEmpty && boundingBoxes.isEmpty)
                    
                    
                }
            }
            .transition(.move(edge: .top))
        }
    }
    
    private func newMask() {
        
    }

    private func resetAll() {
        selectedPoints.removeAll()
        boundingBoxes.removeAll()
        segmentationImages = []
        currentSegmentation = nil
    }
    
    private func undo() {
        if let lastPoint = selectedPoints.last, let lastBox = boundingBoxes.last {
            if lastPoint.dateAdded > lastBox.dateAdded {
                selectedPoints.removeLast()
            } else {
                boundingBoxes.removeLast()
            }
        } else if !selectedPoints.isEmpty {
            selectedPoints.removeLast()
        } else if !boundingBoxes.isEmpty {
            boundingBoxes.removeLast()
        }

        if selectedPoints.isEmpty && boundingBoxes.isEmpty {
            currentSegmentation = nil
        }
    }
}

#Preview {
    ContentView()
}

