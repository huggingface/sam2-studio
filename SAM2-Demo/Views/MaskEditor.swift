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
    
    @State private var bgColor =
    Color(.sRGB, red: 30/255, green: 144/255, blue: 1)
    
    var body: some View {
        //        VStack() {
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
        
        //        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func updateSelectedSegmentationsColor(_ newColor: Color) {
        for id in selectedSegmentations {
            if let index = segmentationImages.firstIndex(where: { $0.id == id }) {
                segmentationImages[index].tintColor = newColor
            }
        }
    }
}

#Preview {
    ContentView()
}
