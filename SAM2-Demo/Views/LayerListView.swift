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
                ForEach(Array(segmentationImages.enumerated()), id: \.element.id) { index, segmentation in
                    AnnotationListView(segmentation: $segmentationImages[index])
                        .padding(.horizontal, 5)
                        .zIndex(Double(index))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                exportMaskToPNG = true
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up.fill")
                            }
                        }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
                
            }
        }
        .listStyle(.sidebar)
    }
    
    func delete(at offsets: IndexSet) {
        segmentationImages.remove(atOffsets: offsets)
    }
    
    func move(from source: IndexSet, to destination: Int) {
        segmentationImages.move(fromOffsets: source, toOffset: destination)
    }
}

#Preview {
    ContentView()
}
