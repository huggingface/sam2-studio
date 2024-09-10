//
//  AnnotationListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct AnnotationListView: View {
    
    @Binding var segmentation: SAMSegmentation
    
    var body: some View {
        HStack {
            Image(nsImage: NSImage(cgImage: segmentation.cgImage, size: NSSize(width: 35, height: 35)))
                .background(.secondary)
                .mask(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading) {
                Text(segmentation.title)
                    .font(.headline)
//                Text(segmentation.firstAppearance)
//                    .font(.subheadline)
//                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("", systemImage: segmentation.isHidden ? "eye.slash.fill" :"eye.fill", action: {
                segmentation.isHidden.toggle()
            })
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
    }
}
