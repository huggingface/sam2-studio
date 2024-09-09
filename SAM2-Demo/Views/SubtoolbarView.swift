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
    @Binding var segmentationImages: [CGImage]

    var body: some View {
        if selectedPoints.count > 0 || boundingBoxes.count > 0 {
            ZStack {
                Rectangle()
                    .fill(.fill.secondary)
                    .frame(height: 30)
                
                HStack {
                    Spacer()
                    Button("Reset", action: resetAll)
                        .padding(.trailing, 5)
                        .disabled(selectedPoints.isEmpty && boundingBoxes.isEmpty)
                }
            }
            .transition(.move(edge: .top))
        }
    }

    private func resetAll() {
        selectedPoints.removeAll()
        boundingBoxes.removeAll()
        segmentationImages = []
    }
}

#Preview {
    ContentView()
}

