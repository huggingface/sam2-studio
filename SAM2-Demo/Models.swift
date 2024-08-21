//
//  Models.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/19/24.
//

import Foundation
import SwiftUI

enum SAMCategoryType: Int {
    case foreground = 0
    case background = 1
    
    var description: String {
        switch self {
        case .foreground:
            return "Foreground"
        case .background:
            return "Background"
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
}


struct SAMPoint: Hashable {
    let id = UUID()
    let coordinates: CGPoint
    let category: SAMCategory
}

struct SAMBox: Hashable, Identifiable {
    let id = UUID()
    var startPoint: CGPoint
    var endPoint: CGPoint
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

let foregroundCat: SAMCategory = SAMCategory(
    type: .foreground,
    name: "Foreground",
    iconName: "square.on.square.dashed",
    color: .pink
)

let backgroundCat: SAMCategory = SAMCategory(
    type: .background,
    name: "Background",
    iconName: "square.on.square.intersection.dashed",
    color: .purple
)
