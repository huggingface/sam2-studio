//
//  AnnotationListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct AnnotationListView: View {
    
    @Binding var segmentation: SAMSegmentation
    @State var showHideIcon: Bool = false
    
    var body: some View {
        HStack {
            Image(nsImage: NSImage(cgImage: segmentation.cgImage, size: NSSize(width: 25, height: 25)))
                .background(.quinary)
                .mask(RoundedRectangle(cornerRadius: 5))
            
            VStack(alignment: .leading) {
                Text(segmentation.title)
                    .font(.headline)
                    .foregroundStyle(segmentation.isHidden ? .tertiary:.primary)
//                Text(segmentation.firstAppearance)
//                    .font(.subheadline)
//                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("", systemImage: segmentation.isHidden ? "eye.slash.fill" :"eye.fill", action: {
                segmentation.isHidden.toggle()
            })
            .opacity(segmentation.isHidden ? 1 : (showHideIcon ? 1:0))
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .onHover { state in
            showHideIcon = state
        }
    }
}
