import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ImageComparisonError: Error, Equatable, LocalizedError {
    case cannotDecode
    case invalidRaster
    case dimensionsTooLarge

    var errorDescription: String? {
        switch self {
        case .cannotDecode: "The image could not be decoded."
        case .invalidRaster: "The image pixel buffer is invalid."
        case .dimensionsTooLarge: "The image dimensions are too large to compare safely."
        }
    }
}

nonisolated struct ImageRaster: Equatable, Sendable {
    let width: Int
    let height: Int
    /// Premultiplied RGBA8, row-major, four bytes per pixel.
    let rgba: Data

    init(width: Int, height: Int, rgba: Data) throws {
        guard width >= 0, height >= 0,
              width <= Int.max / max(height, 1) / 4,
              rgba.count == width * height * 4 else {
            throw ImageComparisonError.invalidRaster
        }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    fileprivate init(validatedWidth width: Int, height: Int, rgba: Data) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    static func decode(_ data: Data, maximumPixels: Int = 25_000_000) throws -> ImageRaster {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw ImageComparisonError.cannotDecode
        }
        guard maximumPixels > 0, width > 0, height > 0,
              width <= maximumPixels / height else {
            throw ImageComparisonError.dimensionsTooLarge
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageComparisonError.cannotDecode
        }
        var pixels = Data(count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                        CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw ImageComparisonError.cannotDecode }
        return try ImageRaster(width: width, height: height, rgba: pixels)
    }
}

nonisolated struct ImageDifferenceResult: Equatable, Sendable {
    let leftWidth: Int
    let leftHeight: Int
    let rightWidth: Int
    let rightHeight: Int
    let differingPixelCount: Int
    let comparedPixelCount: Int
    let maximumChannelDifference: UInt8
    /// Average absolute difference across RGBA channels, normalized to 0...1.
    let meanAbsoluteDifference: Double
    let heatmap: ImageRaster

    var dimensionsMatch: Bool {
        leftWidth == rightWidth && leftHeight == rightHeight
    }

    var identical: Bool {
        dimensionsMatch && differingPixelCount == 0
    }
}

nonisolated enum ImageComparisonEngine {
    static func compare(left: ImageRaster, right: ImageRaster) -> ImageDifferenceResult {
        let width = max(left.width, right.width)
        let height = max(left.height, right.height)
        let totalPixels = width * height
        var heatmap = Data(count: totalPixels * 4)
        var differingPixels = 0
        var differenceSum: UInt64 = 0
        var maximumDifference: UInt8 = 0

        left.rgba.withUnsafeBytes { leftBytes in
            right.rgba.withUnsafeBytes { rightBytes in
                heatmap.withUnsafeMutableBytes { heatmapBytes in
                    let lhs = leftBytes.bindMemory(to: UInt8.self)
                    let rhs = rightBytes.bindMemory(to: UInt8.self)
                    let output = heatmapBytes.bindMemory(to: UInt8.self)
                    for y in 0..<height {
                        for x in 0..<width {
                            let outputOffset = (y * width + x) * 4
                            var pixelMaximum: UInt8 = 0
                            let isInsideLeft = x < left.width && y < left.height
                            let isInsideRight = x < right.width && y < right.height
                            if isInsideLeft && isInsideRight {
                                let leftOffset = (y * left.width + x) * 4
                                let rightOffset = (y * right.width + x) * 4
                                for channel in 0..<4 {
                                    let a = lhs[leftOffset + channel]
                                    let b = rhs[rightOffset + channel]
                                    let difference = a > b ? a - b : b - a
                                    pixelMaximum = max(pixelMaximum, difference)
                                    differenceSum += UInt64(difference)
                                }
                            } else {
                                pixelMaximum = 255
                                differenceSum += 255 * 4
                            }
                            if pixelMaximum > 0 { differingPixels += 1 }
                            maximumDifference = max(maximumDifference, pixelMaximum)
                            output[outputOffset] = 255
                            output[outputOffset + 1] = 0
                            output[outputOffset + 2] = 0
                            output[outputOffset + 3] = pixelMaximum
                        }
                    }
                }
            }
        }

        let denominator = max(Double(totalPixels) * 4.0 * 255.0, 1.0)
        return ImageDifferenceResult(
            leftWidth: left.width,
            leftHeight: left.height,
            rightWidth: right.width,
            rightHeight: right.height,
            differingPixelCount: differingPixels,
            comparedPixelCount: totalPixels,
            maximumChannelDifference: maximumDifference,
            meanAbsoluteDifference: Double(differenceSum) / denominator,
            heatmap: ImageRaster(validatedWidth: width, height: height, rgba: heatmap))
    }
}
