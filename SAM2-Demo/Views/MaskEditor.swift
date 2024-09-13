//
//  MaskEditor.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/10/24.
//

import SwiftUI

struct MaskEditor: View {
    
    @Binding var exportMaskToPNG: Bool
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var selectedSegmentations: Set<SAMSegmentation.ID>
    @Binding var currentSegmentation: SAMSegmentation?
    
    @State private var bgColor =
    Color(.sRGB, red: 30/255, green: 144/255, blue: 1)
    
    var body: some View {
        Form {
            Section {
                ColorPicker("Color", selection: $bgColor)
                    .onChange(of: bgColor) { oldColor, newColor in
                        updateSelectedSegmentationsColor(newColor)
                    }
                
                Button("Export Selected...", action: {
                    exportMaskToPNG = true
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedSegmentations) { oldValue, newValue in
            bgColor = getColorOfFirstSelectedSegmentation()
        }
        .onAppear {
            bgColor = getColorOfFirstSelectedSegmentation()
        }
        
    }
    
    private func updateSelectedSegmentationsColor(_ newColor: Color) {
        for id in selectedSegmentations {
            if let index = segmentationImages.firstIndex(where: { $0.id == id }) {
                segmentationImages[index].tintColor = newColor
            }
        }
    }
    
    private func getColorOfFirstSelectedSegmentation() -> Color {
        if let firstSelectedId = selectedSegmentations.first,
           let firstSelectedSegmentation = segmentationImages.first(where: { $0.id == firstSelectedId }) {
            return firstSelectedSegmentation.tintColor
        }
        return bgColor // Return default color if no segmentation is selected
    }
}

#Preview {
    ContentView()
}
