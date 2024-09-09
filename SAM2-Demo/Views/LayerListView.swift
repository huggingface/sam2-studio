//
//  LayerListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct LayerListView: View {
    
    @Binding var segmentationImages: [SAMSegmentation]
    @State var selectedSegmentations = Set<SAMSegmentation.ID>()
    
    var body: some View {
        List(selection: $selectedSegmentations) {
                    Section("Annotations List") {
                        ForEach($segmentationImages, id: \.id) { segmentationImage in
                            AnnotationListView(segmentation: segmentationImage)
                                .padding(.horizontal, 5)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let index = segmentationImages.firstIndex(where: { $0.id == segmentationImage.id }) {
                                                    segmentationImages.remove(at: index)
                                                }
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
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
