//
//  LayerListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct LayerListView: View {
    
    @Binding var segmentationImages: [SAMSegmentation]
    
    var body: some View {
        List {
            Section("Annotations List") {
                ForEach($segmentationImages) { segmentationImage in
                    AnnotationListView(segmentation: segmentationImage)
                        .padding(.horizontal)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

#Preview {
    ContentView()
}
