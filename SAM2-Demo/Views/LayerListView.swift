//
//  LayerListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct LayerListView: View {
    
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var exportMaskToPNG: Bool
    @Binding var selectedSegmentations: Set<SAMSegmentation.ID>
    
    var body: some View {
        List(selection: $selectedSegmentations) {
                    Section("Annotations List") {
                        ForEach($segmentationImages, id: \.id) { segmentationImage in
                            AnnotationListView(segmentation: segmentationImage)
                                .padding(.horizontal, 5)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        exportMaskToPNG = true
                                    } label: {
                                        Label("Export", systemImage: "square.and.arrow.up.fill")
                                    }
                                }
                        }
                        .onDelete(perform: delete)
                        
                    }
                }
        .listStyle(.sidebar)
    }
    
    func delete(at offsets: IndexSet) {
        segmentationImages.remove(atOffsets: offsets)
    }
}

#Preview {
    ContentView()
}
