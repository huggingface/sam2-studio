//
//  Color+Extension.swift
//  SAM2-Demo
//
//  Created by Fleetwood on 01/10/2024.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    #if canImport(UIKit)
    var asNative: UIColor { UIColor(self) }
    #elseif canImport(AppKit)
    var asNative: NSColor { NSColor(self) }
    #endif

    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let color = asNative.usingColorSpace(.deviceRGB)!
        var t = (CGFloat(), CGFloat(), CGFloat(), CGFloat())
        color.getRed(&t.0, green: &t.1, blue: &t.2, alpha: &t.3)
        return t
    }
}

func colorDistance(_ color1: Color, _ color2: Color) -> Double {
    let rgb1 = color1.rgba;
    let rgb2 = color2.rgba;

    let rDiff = rgb1.red - rgb2.red
    let gDiff = rgb1.green - rgb2.green
    let bDiff = rgb1.blue - rgb2.blue

    return sqrt(rDiff*rDiff + gDiff*gDiff + bDiff*bDiff)
}

// Determine the Euclidean distance of all candidates from current set of colors.
// Find the **maximum min-distance** from all current colors.
func furthestColor(from existingColors: [Color], among candidateColors: [Color]) -> Color {
    var maxMinDistance: Double = 0
    var furthestColor: Color = SAMSegmentation.randomCandidateColor() ?? SAMSegmentation.defaultColor

    for candidate in candidateColors {
        let minDistance = existingColors.map { colorDistance(candidate, $0) }.min() ?? 0
        if minDistance > maxMinDistance {
            maxMinDistance = minDistance
            furthestColor = candidate
        }
    }

    return furthestColor
}
