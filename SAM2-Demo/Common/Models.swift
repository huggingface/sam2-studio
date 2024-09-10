//
//  Models.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/19/24.
//

import Foundation
import SwiftUI

enum SAMCategoryType: Int {
    case background = 0
    case foreground = 1
    case boxOrigin = 2
    case boxEnd = 3

    var description: String {
        switch self {
        case .foreground:
            return "Foreground"
        case .background:
            return "Background"
        case .boxOrigin:
            return "Box Origin"
        case .boxEnd:
            return "Box End"
        }
    }
}

struct SAMCategory: Hashable {
    let id: UUID = UUID()
    let type: SAMCategoryType
    let name: String
    let iconName: String
    let color: Color

    var typeDescription: String {
        type.description
    }

    static let foreground = SAMCategory(
        type: .foreground,
        name: "Foreground",
        iconName: "square.on.square.dashed",
        color: .pink
    )

    static let background = SAMCategory(
        type: .background,
        name: "Background",
        iconName: "square.on.square.intersection.dashed",
        color: .purple
    )

    static let boxOrigin = SAMCategory(
        type: .boxOrigin,
        name: "Box Origin",
        iconName: "",
        color: .white
    )

    static let boxEnd = SAMCategory(
        type: .boxEnd,
        name: "Box End",
        iconName: "",
        color: .white
    )
}


struct SAMPoint: Hashable {
    let id = UUID()
    let coordinates: CGPoint
    let normalizedCoordinate: CGPoint
    let category: SAMCategory
    
    init(coordinates: CGPoint, imageSize: CGSize, currentScale: CGFloat, category: SAMCategory) {
        self.coordinates = coordinates
        self.normalizedCoordinate = SAMPoint.normalize(coordinates, at: currentScale, for: imageSize)
        self.category = category
    }
    
    static func normalize(_ coordinate: CGPoint, at currentScale: CGFloat, for size: CGSize) -> CGPoint {
        return CGPoint(
            x: (coordinate.x - size.width / 2) / (size.width / 2 * currentScale),
            y: (coordinate.y - size.height / 2) / (size.height / 2 * currentScale)
        )
    }
    
    func denormalize(for size: CGSize, at currentScale: CGFloat) -> CGPoint {
        return CGPoint(
            x: normalizedCoordinate.x * (size.width / 2 * currentScale) + (size.width / 2),
            y: normalizedCoordinate.y * (size.height / 2 * currentScale) + (size.height / 2)
        )
    }
}

struct SAMBox: Hashable, Identifiable {
    let id = UUID()
    var startPoint: CGPoint
    var endPoint: CGPoint
    let category: SAMCategory
}

extension SAMBox {
    var points: [SAMPoint] {
        [SAMPoint(coordinates: startPoint, imageSize: CGSize(width: 1024, height: 1024), currentScale: 1.0, category: .boxOrigin),
         SAMPoint(coordinates: endPoint, imageSize: CGSize(width: 1024, height: 1024), currentScale: 1.0, category: .boxEnd)]
    }
}

struct SAMSegmentation: Hashable, Identifiable {
    let id = UUID()
    var image: CGImage
    var title: String = ""
    var firstAppearance: Int?
    var isHidden: Bool = false
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
