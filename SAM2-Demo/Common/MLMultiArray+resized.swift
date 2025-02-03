//
//  MLMultiArray+resized.swift
//  SAM2-Demo
//
//  Created by Martin Stachon on 16.01.2025.
//

import CoreML

extension MLMultiArray {
    func resizedMaskArray(toSize size: CGSize) throws -> MLMultiArray {
        let (H, W) = (self.shape[0].intValue, self.shape[1].intValue) // Input dimensions
        let (newH, newW) = (Int(size.height), Int(size.width))

        // Create output array with target size
        let outputShape = [1, 1, NSNumber(value: newH), NSNumber(value: newW)]
        let output = try MLMultiArray(shape: outputShape, dataType: self.dataType)

        // Calculate scaling factors
        let scaleH = Double(H - 1) / Double(newH - 1)
        let scaleW = Double(W - 1) / Double(newW - 1)

        // Iterate through target coordinates
        for y in 0..<newH {
            for x in 0..<newW {
                // Calculate source coordinates
                let srcY = Double(y) * scaleH
                let srcX = Double(x) * scaleW

                // Get corner coordinates
                let y1 = Int(floor(srcY))
                let y2 = min(y1 + 1, H - 1)
                let x1 = Int(floor(srcX))
                let x2 = min(x1 + 1, W - 1)

                // Calculate interpolation weights
                let wy2 = srcY - Double(y1)
                let wy1 = 1.0 - wy2
                let wx2 = srcX - Double(x1)
                let wx1 = 1.0 - wx2

                // Get corner values
                let f11 = self[[y1, x1] as [NSNumber]].doubleValue
                let f21 = self[[y2, x1] as [NSNumber]].doubleValue
                let f12 = self[[y1, x2] as [NSNumber]].doubleValue
                let f22 = self[[y2, x2] as [NSNumber]].doubleValue

                // Perform bilinear interpolation
                let interpolated = wy1 * (wx1 * f11 + wx2 * f12) +
                wy2 * (wx1 * f21 + wx2 * f22)

                // Set output value
                output[[0, 0, y, x] as [NSNumber]] = NSNumber(value: interpolated)
            }
        }

        return output
    }
}
