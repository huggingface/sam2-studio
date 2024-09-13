//
//  LayerListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct LayerListView: View {
    
    @Binding var segmentationImages: [SAMSegmentation]
    @Binding var selectedSegmentations: Set<SAMSegmentation.ID>
    @Binding var currentSegmentation: SAMSegmentation?
    
    var body: some View {
        List(selection: $selectedSegmentations) {
            Section("Annotations List") {
                ForEach(Array(segmentationImages.enumerated()), id: \.element.id) { index, segmentation in
                    AnnotationListView(segmentation: $segmentationImages[index])
                        .padding(.horizontal, 5)
                        .contextMenu {
                            Button(role: .destructive) {
                                if let index = segmentationImages.firstIndex(where: { $0.id == segmentation.id }) {
                                    segmentationImages.remove(at: index)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)

                if let currentSegmentation = currentSegmentation {
                    AnnotationListView(segmentation: .constant(currentSegmentation))
                        .tag(currentSegmentation.id)
                }
                
                
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
