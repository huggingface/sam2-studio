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

struct ContentView: View {
    
    // ML Models
    @StateObject private var sam2 = SAM2()
    @State private var segmentationImage: CGImage?
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
    var categories: [SAMCategory] = [foregroundCat, backgroundCat]
    
    @State private var selectedTool: SAMTool?
    @State private var selectedCategory: SAMCategory?
    @State private var selectedPoints: [SAMPoint] = []
    @State private var boundingBoxes: [SAMBox] = []
    @State private var currentBox: SAMBox?
    @State private var originalSize: NSSize?
    
    @ViewBuilder
    var pointsOverlay: some View {
        if selectedPoints.count > 0 {
            ForEach(selectedPoints, id: \.self) { point in
                Image(systemName: "circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(point.category.color)
                    .position(
                        x: point.coordinates.x,
                        y: point.coordinates.y
                    )
                    .onTapGesture {
                        if selectedTool == eraserTool {
                            selectedPoints.removeAll { $0.id == point.id }
                        }
                    }
            }
        }
    }
    
    @ViewBuilder
    var boundingBoxesOverlay: some View {
        ForEach(boundingBoxes) { box in
            Path { path in
                path.move(to: box.startPoint)
                path.addLine(to: CGPoint(x: box.endPoint.x, y: box.startPoint.y))
                path.addLine(to: box.endPoint)
                path.addLine(to: CGPoint(x: box.startPoint.x, y: box.endPoint.y))
                path.closeSubpath()
            }
            .stroke(
                box.category.color,
                style: StrokeStyle(
                    lineWidth: 2,
                    dash: [5, 5]
                )
            )
        }
        if let currentBox = currentBox {
            Path { path in
                path.move(to: currentBox.startPoint)
                path.addLine(to: CGPoint(x: currentBox.endPoint.x, y: currentBox.startPoint.y))
                path.addLine(to: currentBox.endPoint)
                path.addLine(to: CGPoint(x: currentBox.startPoint.x, y: currentBox.endPoint.y))
                path.closeSubpath()
            }
            .stroke(
                currentBox.category.color,
                style: StrokeStyle(
                    lineWidth: 2,
                    dash: [5, 5]
                )
            )
        }
    }
    
    @ViewBuilder
    var segmentationOverlay: some View {
        if let segmentationImage = segmentationImage {
            let nsImage = NSImage(cgImage: segmentationImage, size: imageSize)
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .allowsHitTesting(false)
                .frame(width: imageSize.width, height: imageSize.height)
                .opacity(0.7)
                
        }
    }
    
    var body: some View {
        ZStack {
            VStack {
                // Sub-toolbar
                // If SAM is instantaneous, this could be used for something else?
                if selectedPoints.count > 0 || boundingBoxes.count > 0 {
                    ZStack {
                        Rectangle()
                            .fill(.fill.secondary)
                            .frame(height: 30)
                        
                        HStack {
                            Spacer()
                            Button("Reset", action: {
                                selectedPoints.removeAll()
                                boundingBoxes.removeAll()
                                segmentationImage = nil
                            })
                            .padding(.trailing, 5)
                            .disabled(selectedPoints.count == 0)
                        }
                    }
                    .transition(.move(edge: .top))
                    
                }
                ScrollView([.vertical, .horizontal]) {
                    if let image = displayImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 500, maxHeight: 500)
                            .onTapGesture(coordinateSpace: .local) { location in
                                if selectedTool == pointTool {
                                    placePoint(at: location)
                                    performForwardPass()
                                }
                            }
                            .gesture(boundingBoxGesture)
                            .onHover { inside in
                                changeCursorAppearance(is: inside)
                            }
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
                                }
                            )
                            .onPreferenceChange(SizePreferenceKey.self) { size in
                                imageSize = size
                            }
                            .overlay {
                                pointsOverlay
                                boundingBoxesOverlay
                                segmentationOverlay
                            }
                    } else {
                        ContentUnavailableView("No Image Loaded", systemImage: "photo.fill.on.rectangle.fill", description: Text("Please use the '+' button to import a file."))
                    }
                }
            }
        }
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
    
    private func placePoint(at coordinates: CGPoint) {
        let samPoint = SAMPoint(coordinates: coordinates, category: selectedCategory!)
        self.selectedPoints.append(samPoint)
    }
    
    private var boundingBoxGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard selectedTool == boundingBoxTool else { return }
                
                if currentBox == nil {
                    currentBox = SAMBox(startPoint: value.startLocation, endPoint: value.location, category: selectedCategory!)
                } else {
                    currentBox?.endPoint = value.location
                }
            }
            .onEnded { value in
                guard selectedTool == boundingBoxTool else { return }
                
                if let box = currentBox {
                    boundingBoxes.append(box)
                    currentBox = nil
                }
            }
    }
    
    private func changeCursorAppearance(is inside: Bool) {
        if inside {
            if selectedTool == pointTool {
                NSCursor.pointingHand.push()
            } else if selectedTool == boundingBoxTool {
                NSCursor.crosshair.push()
            }
        } else {
            NSCursor.pop()
        }
    }
    
    
    // MARK: ML Methods
    private func performForwardPass() {
        Task {
            do {
                try await sam2.getPromptEncoding(from: self.selectedPoints, with: originalSize ?? .zero)
                let cgImageMask = try await sam2.getMask(for: originalSize ?? .zero)
                if let cgImageMask {
                    DispatchQueue.main.async {
                        self.segmentationImage = cgImageMask
                    }
                }
            } catch {
                self.error = error
            }
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
