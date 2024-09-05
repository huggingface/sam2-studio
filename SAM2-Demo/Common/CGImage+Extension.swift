//
//  CGImage+Extension.swift
//  SAM2-Demo
//
//  Created by Cyril Zakka on 8/20/24.
//

import ImageIO

extension CGImage {
    func resized(to size: CGSize) -> CGImage? {
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)

        let bytesPerPixel = self.bitsPerPixel / 8
        let destBytesPerRow = width * bytesPerPixel

        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: self.bitsPerComponent,
                                      bytesPerRow: destBytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: self.bitmapInfo.rawValue)
        else { return nil }

        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }
}
