import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreML

import os

// TODO: Add reset, bounding box, and eraser

let logger = Logger(
    subsystem:
        "com.cyrilzakka.SAM2-Demo.ContentView",
    category: "ContentView")


struct PointsOverlay: View {
    @Binding var selectedPoints: [SAMPoint]
    @Binding var currentScale: CGFloat
    @Binding var imageSize: CGSize
    @Binding var selectedTool: SAMTool?
    
    var body: some View {
        ForEach(selectedPoints, id: \.self) { point in
            Image(systemName: "circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(point.category.color)
                .position(computePosition(point: point))
                .onTapGesture {
                    if selectedTool == eraserTool {
                        selectedPoints.removeAll { $0.id == point.id }
                    }
                }
        }
    }
    
    private func computePosition(point: SAMPoint) -> CGPoint {
        point.denormalize(for: imageSize, at: currentScale)
    }
}

struct BoundingBoxesOverlay: View {
    let boundingBoxes: [SAMBox]
    let currentBox: SAMBox?
    
    var body: some View {
        ForEach(boundingBoxes) { box in
            BoundingBoxPath(box: box)
        }
        if let currentBox = currentBox {
            BoundingBoxPath(box: currentBox)
        }
    }
}

struct BoundingBoxPath: View {
    let box: SAMBox
    
    var body: some View {
        Path { path in
            path.move(to: box.startPoint)
            path.addLine(to: CGPoint(x: box.endPoint.x, y: box.startPoint.y))
            path.addLine(to: box.endPoint)
            path.addLine(to: CGPoint(x: box.startPoint.x, y: box.endPoint.y))
            path.closeSubpath()
        }
        .stroke(
            box.category.color,
            style: StrokeStyle(lineWidth: 2, dash: [5, 5])
        )
    }
}

struct SegmentationOverlay: View {
    
    @Binding var segmentationImage: SAMSegmentation
    @Binding var currentScale: CGFloat
    let imageSize: CGSize
    
    var body: some View {
        let nsImage = NSImage(cgImage: segmentationImage.image, size: imageSize)
        Image(nsImage: nsImage)
            .resizable()
            .scaleEffect(currentScale)
            .allowsHitTesting(false)
            .frame(width: imageSize.width, height: imageSize.height)
            .opacity(segmentationImage.isHidden ? 0:0.7)
            .onAppear {
                print(imageSize)
            }
    }
}

struct ContentView: View {
    
    // ML Models
    @StateObject private var sam2 = SAM2()
    @State private var segmentationImages: [SAMSegmentation] = []
    @State private var imageSize: CGSize = .zero
    
    // File importer
    @State private var imageURL: URL?
    @State private var isImportingFromFiles: Bool = false
    @State private var displayImage: NSImage?
    
    // Photos Picker
    @State private var isImportingFromPhotos: Bool = false
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var error: Error?
    
    // ML Model Properties
    var tools: [SAMTool] = [normalTool, pointTool, boundingBoxTool, eraserTool]
    var categories: [SAMCategory] = [.foreground, .background]
    
    @State private var selectedTool: SAMTool?
    @State private var selectedCategory: SAMCategory?
    @State private var selectedPoints: [SAMPoint] = []
    @State private var boundingBoxes: [SAMBox] = []
    @State private var currentBox: SAMBox?
    @State private var originalSize: NSSize?
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        NavigationSplitView(sidebar: {
            LayerListView(segmentationImages: $segmentationImages)
                .frame(minWidth: 200, idealWidth: 300, maxWidth: 400)
        }, detail: {
            ZStack {
                VStack {
                    SubToolbar(selectedPoints: $selectedPoints, boundingBoxes: $boundingBoxes, segmentationImages: $segmentationImages)
                    
                    ScrollView([.vertical, .horizontal]) {
                        if let image = displayImage {
                            ImageView(image: image, currentScale: $currentScale, selectedTool: $selectedTool, selectedCategory: $selectedCategory, selectedPoints: $selectedPoints, boundingBoxes: $boundingBoxes, currentBox: $currentBox, segmentationImages: $segmentationImages, imageSize: $imageSize, originalSize: $originalSize, sam2: sam2)
                        } else {
                            ContentUnavailableView("No Image Loaded", systemImage: "photo.fill.on.rectangle.fill", description: Text("Please use the '+' button to import a file."))
                        }
                    }
                }
            }
        })
        .toolbar {
            // Tools
            ToolbarItemGroup(placement: .principal) {
                Picker(selection: $selectedTool, content: {
                    ForEach(tools, id: \.self) { tool in
                        Label(tool.name, systemImage: tool.iconName)
                            .tag(tool)
                            .labelStyle(.titleAndIcon)
                    }
                }, label: {
                    Label("Tools", systemImage: "pencil.and.ruler")
                })
                .pickerStyle(.menu)
                
                Picker(selection: $selectedCategory, content: {
                    ForEach(categories, id: \.self) { cat in
                        Label(cat.name, systemImage: cat.iconName)
                            .tag(cat)
                            .labelStyle(.titleAndIcon)
                    }
                }, label: {
                    Label("Tools", systemImage: "pencil.and.ruler")
                })
                .pickerStyle(.menu)
                
            }
            
            // Import
            ToolbarItemGroup {
                Menu {
                    Button(action: {
                        isImportingFromPhotos = true
                    }, label: {
                        Label("From Photos", systemImage: "photo.on.rectangle.angled.fill")
                    })
                    
                    Button(action: {
                        isImportingFromFiles = true
                    }, label: {
                        Label("From Files", systemImage: "folder.fill")
                    })
                } label: {
                    Label("Import", systemImage: "photo.badge.plus")
                }
            }
        }
        
        .onAppear {
            if selectedTool == nil {
                selectedTool = tools.first
            }
            if selectedCategory == nil {
                selectedCategory = categories.first
            }
            
        }
        
        // MARK: - Image encoding
        .onChange(of: displayImage) {
            segmentationImages = []
            Task {
                if let displayImage, let pixelBuffer = displayImage.pixelBuffer(width: 1024, height: 1024) {
                    originalSize = displayImage.size
                    do {
                        try await sam2.getImageEncoding(from: pixelBuffer)
                    } catch {
                        self.error = error
                    }
                }
            }
        }
        
        // MARK: - Photos Importer
        .photosPicker(isPresented: $isImportingFromPhotos, selection: $selectedItem, matching: .any(of: [.images, .screenshots, .livePhotos]))
        .onChange(of: selectedItem) {
            Task {
                if let loadedData = try? await
                    selectedItem?.loadTransferable(type: Data.self) {
                    DispatchQueue.main.async {
                        selectedPoints.removeAll()
                        displayImage = NSImage(data: loadedData)
                    }
                } else {
                    logger.error("Error loading image from Photos.")
                }
            }
        }
        
        // MARK: - File Importer
        .fileImporter(isPresented: $isImportingFromFiles,
                      allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let file):
                self.selectedItem = nil
                self.selectedPoints.removeAll()
                self.imageURL = file
                loadImage(from: file)
            case .failure(let error):
                logger.error("File import error: \(error.localizedDescription)")
                self.error = error
            }
        }
    }
    
    // MARK: - Private Methods
    private func loadImage(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Failed to access the file. Security-scoped resource access denied.")
            return
        }
        
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let imageData = try Data(contentsOf: url)
            if let image = NSImage(data: imageData) {
                DispatchQueue.main.async {
                    self.displayImage = image
                }
            } else {
                logger.error("Failed to create NSImage from file data")
            }
        } catch {
            logger.error("Error loading image data: \(error.localizedDescription)")
            self.error = error
        }
    }
    
    
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

#Preview {
    ContentView()
}
