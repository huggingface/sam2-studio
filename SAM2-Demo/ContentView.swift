import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

import os

// TODO: Add reset, bounding box, and eraser

let logger = Logger(
    subsystem:
        "com.cyrilzakka.SAM2-Demo.ContentView",
    category: "ContentView")


struct SAMCategory: Hashable {
    let id: UUID = UUID()
    let name: String
    let iconName: String
    let color: Color
}

struct SAMPoint: Hashable {
    let id = UUID()
    let coordinates: CGPoint
    let category: SAMCategory
}

struct SAMTool: Hashable {
    let id: UUID = UUID()
    let name: String
    let iconName: String
}

// Tools
let normalTool: SAMTool = SAMTool(name: "Selector", iconName: "cursorarrow")
let pointTool: SAMTool = SAMTool(name: "Point", iconName: "hand.point.up.left")
let boundingBoxTool: SAMTool = SAMTool(name: "Bounding Box", iconName: "rectangle.dashed")
let eraserTool: SAMTool = SAMTool(name: "Eraser", iconName: "eraser")

// Categories
let foregroundCat: SAMCategory = SAMCategory(name: "Foreground", iconName: "square.on.square.dashed", color: .pink)
let backgroundCat: SAMCategory = SAMCategory(name: "Background", iconName: "square.on.square.intersection.dashed", color: .purple)

struct ContentView: View {
    
    // File importer
    @State private var imageURL: URL?
    @State private var isImportingFromFiles: Bool = false
    @State private var displayImage: NSImage?
    
    // Photos Picker
    @State private var isImportingFromPhotos: Bool = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var photosImage: Image?
    
    @State private var error: Error?
    
    // ML Model Properties
    var tools: [SAMTool] = [normalTool, pointTool, boundingBoxTool, eraserTool]
    var categories: [SAMCategory] = [foregroundCat, backgroundCat]
    
    @State private var selectedTool: SAMTool?
    @State private var selectedCategory: SAMCategory?
    @State private var selectedPoints: [SAMPoint] = []
    
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
    
    
    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .onTapGesture(coordinateSpace: .local) { location in
                        if selectedTool == pointTool {
                            placePoint(at: location)
                        }
                    }
                    .onHover { inside in
                        changeCursorAppearance(is: inside)
                    }
                    .overlay {
                        pointsOverlay
                    }
            } else if let photosImage {
                photosImage
                    .resizable()
                    .scaledToFit()
                    .onTapGesture(coordinateSpace: .local) { location in
                        if selectedTool == pointTool {
                            placePoint(at: location)
                        }
                    }
                    .onHover { inside in
                        changeCursorAppearance(is: inside)
                    }
                    .overlay {
                        pointsOverlay
                    }
            } else {
                ContentUnavailableView("No Image Loaded", systemImage: "photo.fill.on.rectangle.fill", description: Text("Please use the '+' button to import a file."))
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
        
        // MARK: - Photos Importer
        .photosPicker(isPresented: $isImportingFromPhotos, selection: $selectedItem, matching: .any(of: [.images, .screenshots, .livePhotos]))
        .onChange(of: selectedItem) {
            Task {
                if let loaded = try? await
                    selectedItem?.loadTransferable(type: Image.self) {
                    displayImage = nil
                    selectedPoints.removeAll()
                    photosImage = loaded
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
                self.photosImage = nil
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
}

#Preview {
    ContentView()
}
