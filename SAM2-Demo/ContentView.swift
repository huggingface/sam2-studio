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
    @Binding var selectedTool: SAMTool?
    let imageSize: CGSize

    var body: some View {
        ForEach(selectedPoints, id: \.self) { point in
            Image(systemName: "circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(point.category.color)
                .position(point.coordinates.toSize(imageSize))
                .onTapGesture {
                    print(point.coordinates)
                    if selectedTool == eraserTool {
                        selectedPoints.removeAll { $0.id == point.id }
                    }
                }
        }
    }
}

struct BoundingBoxesOverlay: View {
    let boundingBoxes: [SAMBox]
    let currentBox: SAMBox?
    let imageSize: CGSize

    var body: some View {
        ForEach(boundingBoxes) { box in
            BoundingBoxPath(box: box, imageSize: imageSize)
        }
        if let currentBox = currentBox {
            BoundingBoxPath(box: currentBox, imageSize: imageSize)
        }
    }
}

struct BoundingBoxPath: View {
    let box: SAMBox
    let imageSize: CGSize

    var body: some View {
        Path { path in
            path.move(to: box.startPoint.toSize(imageSize))
            path.addLine(to: CGPoint(x: box.endPoint.x, y: box.startPoint.y).toSize(imageSize))
            path.addLine(to: box.endPoint.toSize(imageSize))
            path.addLine(to: CGPoint(x: box.startPoint.x, y: box.endPoint.y).toSize(imageSize))
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
    let imageSize: CGSize
    
    @State var counter: Int = 0
    var origin: CGPoint = .zero
    var shouldAnimate: Bool = false

    var body: some View {
        let nsImage = NSImage(cgImage: segmentationImage.cgImage, size: imageSize)
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .allowsHitTesting(false)
                .frame(width: imageSize.width, height: imageSize.height)
                .opacity(segmentationImage.isHidden ? 0:0.6)
                .modifier(RippleEffect(at: CGPoint(x: segmentationImage.cgImage.width/2, y: segmentationImage.cgImage.height/2), trigger: counter))
                .onAppear {
                    print("imageSize: \(imageSize)")
                    if shouldAnimate {
                        counter += 1
                    }
                }
    }
}

struct ContentView: View {
    
    // ML Models
    @StateObject private var sam2 = SAM2()
    @State private var currentSegmentation: SAMSegmentation?
    @State private var segmentationImages: [SAMSegmentation] = []
    @State private var imageSize: CGSize = .zero
    
    // File importer
    @State private var imageURL: URL?
    @State private var isImportingFromFiles: Bool = false
    @State private var displayImage: NSImage?
    
    // Mask exporter
    @State private var exportURL: URL?
    @State private var exportMaskToPNG: Bool = false
    @State private var showInspector: Bool = true
    @State private var selectedSegmentations = Set<SAMSegmentation.ID>()
    
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
            VStack {
                LayerListView(segmentationImages: $segmentationImages, selectedSegmentations: $selectedSegmentations, currentSegmentation: $currentSegmentation)
                Spacer()
                Button(action: {
                    if let currentSegmentation = self.currentSegmentation {
                        self.segmentationImages.append(currentSegmentation)
                        self.reset()
                    }
                }, label: {
                    Text("New Mask")
                        
                }).padding()
            }
        }, detail: {
            ZStack {
                VStack(spacing: 0) {
                    SubToolbar(selectedPoints: $selectedPoints, boundingBoxes: $boundingBoxes, segmentationImages: $segmentationImages, currentSegmentation: $currentSegmentation)
                    
                    ZoomableScrollView {
                        if let image = displayImage {
                            ImageView(image: image, currentScale: $currentScale, selectedTool: $selectedTool, selectedCategory: $selectedCategory, selectedPoints: $selectedPoints, boundingBoxes: $boundingBoxes, currentBox: $currentBox, segmentationImages: $segmentationImages, currentSegmentation: $currentSegmentation, imageSize: $imageSize, originalSize: $originalSize, sam2: sam2)
                        } else {
                            ContentUnavailableView("No Image Loaded", systemImage: "photo.fill.on.rectangle.fill", description: Text("Please import a photo to get started."))
                        }
                    }
                }
            }
        })
        .inspector(isPresented: $showInspector, content: {
            if selectedSegmentations.isEmpty {
                ContentUnavailableView(label: {
                    Label(title: {
                        Text("No Mask Selected")
                            .font(.subheadline)
                    }, icon: {})
                    
                })
                .inspectorColumnWidth(min: 200, ideal: 200, max: 200)
            } else {
                MaskEditor(exportMaskToPNG: $exportMaskToPNG, segmentationImages: $segmentationImages, selectedSegmentations: $selectedSegmentations, currentSegmentation: $currentSegmentation)
                    .inspectorColumnWidth(min: 200, ideal: 200, max: 200)
                    .toolbar {
                        Spacer()
                        Button {
                            showInspector.toggle()
                        } label: {
                            Label("Toggle Inspector", systemImage: "sidebar.trailing")
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
                selectedTool = tools[1]
            }
            if selectedCategory == nil {
                selectedCategory = categories.first
            }
           
        }

        // MARK: - Image encoding
        .onChange(of: displayImage) {
            segmentationImages = []
            self.reset()
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
        
        // MARK: - File exporter
                      .fileExporter(
                        isPresented: $exportMaskToPNG,
                        document: DirectoryDocument(initialContentType: .folder),
                        contentType: .folder,
                        defaultFilename: "Segmentations"
                      ) { result in
                          if case .success(let url) = result {
                              exportURL = url
                              let selectedToExport = segmentationImages.filter { segmentation in
                                  selectedSegmentations.contains(segmentation.id)
                              }
                              exportSegmentations(selectedToExport, to: url)
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
    
    func exportSegmentations(_ segmentations: [SAMSegmentation], to directory: URL) {
        let fileManager = FileManager.default
        
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            
            for (index, segmentation) in segmentations.enumerated() {
                let filename = "segmentation_\(index + 1).png"
                let fileURL = directory.appendingPathComponent(filename)
                
                if let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, segmentation.cgImage, nil)
                    if CGImageDestinationFinalize(destination) {
                        print("Saved segmentation \(index + 1) to \(fileURL.path)")
                    } else {
                        print("Failed to save segmentation \(index + 1)")
                    }
                }
            }
        } catch {
            print("Error creating directory: \(error.localizedDescription)")
        }
    }
    
    private func reset() {
        selectedPoints = []
        boundingBoxes = []
        currentBox = nil
        currentSegmentation = nil
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
