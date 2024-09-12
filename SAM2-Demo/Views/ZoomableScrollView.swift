//
//  ZoomableScrollView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/12/24.
//

import AppKit
import SwiftUI

struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 20
        scrollView.minMagnification = 1

        let hostedView = context.coordinator.hostingView
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.width, .height]
        hostedView.frame = scrollView.bounds
        scrollView.documentView = hostedView

        return scrollView
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(hostingView: NSHostingView(rootView: self.content))
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.hostingView.rootView = self.content
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>

        init(hostingView: NSHostingView<Content>) {
            self.hostingView = hostingView
        }
    }
}
