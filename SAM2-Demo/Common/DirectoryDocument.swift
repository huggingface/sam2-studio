//
//  DirectoryDocument.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 9/10/24.
//


import SwiftUI
import UniformTypeIdentifiers

struct DirectoryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    init(initialContentType: UTType = .folder) {
        // Initialize if needed
    }

    init(configuration: ReadConfiguration) throws {
        // Initialize if needed
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(directoryWithFileWrappers: [:])
    }
}
