//
//  ZoomableScrollView.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/12/24.
//

import AppKit
import SwiftUI

struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    @Binding var visibleRect: CGRect
    private var content: Content

    init(visibleRect: Binding<CGRect>, @ViewBuilder content: () -> Content) {
        self._visibleRect = visibleRect
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
        let coordinator = Coordinator(hostingView: NSHostingView(rootView: self.content), parent: self)
        coordinator.listen()
        return coordinator
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.hostingView.rootView = self.content
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var hostingView: NSHostingView<Content>
        var parent: ZoomableScrollView<Content>

        init(hostingView: NSHostingView<Content>, parent: ZoomableScrollView<Content>) {
            self.hostingView = hostingView
            self.parent = parent
        }

        func listen() {
            NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: nil, queue: nil) { notification in
                let scrollView = notification.object as! NSScrollView
                print("did magnify: \(scrollView.magnification), \(scrollView.documentVisibleRect)")
                self.parent.visibleRect = scrollView.documentVisibleRect
            }
            NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: nil, queue: nil) { notification in
                let scrollView = notification.object as! NSScrollView
                print("did scroll: \(scrollView.magnification), \(scrollView.documentVisibleRect)")
                self.parent.visibleRect = scrollView.documentVisibleRect
            }
        }
    }
}
