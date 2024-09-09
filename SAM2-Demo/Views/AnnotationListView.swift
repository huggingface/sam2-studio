//
//  AnnotationListView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/8/24.
//

import SwiftUI

struct AnnotationListView: View {
    
    @State var isHidden: Bool = false
    
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 10)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading) {
                Text("Object Name")
                    .font(.headline)
                Text("Frame")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("", systemImage: isHidden ? "eye.slash.fill" :"eye.fill", action: {
                isHidden.toggle()
            })
            .buttonStyle(.borderless)
        }
    }
}

#Preview {
    AnnotationListView()
}
