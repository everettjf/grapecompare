import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Vision

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

    static func decode(
        _ data: Data,
        formatHint: String?,
        maximumPixels: Int = 25_000_000
    ) throws -> ImageRaster {
        guard formatHint?.lowercased() == "svg" else {
            return try decode(data, maximumPixels: maximumPixels)
        }
        guard let vector = NSImage(data: data) else { throw ImageComparisonError.cannotDecode }
        let width = Int(vector.size.width.rounded(.up))
        let height = Int(vector.size.height.rounded(.up))
        guard maximumPixels > 0, width > 0, height > 0,
              width <= maximumPixels / height else { throw ImageComparisonError.dimensionsTooLarge }
        var proposed = NSRect(x: 0, y: 0, width: width, height: height)
        guard let image = vector.cgImage(forProposedRect: &proposed, context: nil, hints: [
            .interpolation: NSImageInterpolation.none
        ]) else { throw ImageComparisonError.cannotDecode }
        var pixels = Data(count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let base = bytes.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
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

nonisolated struct ImageMetadata: Equatable, Sendable {
    let formatIdentifier: String
    let width: Int
    let height: Int
    let depth: Int?
    let colorModel: String?
    let profileName: String?
    let dpiWidth: Double?
    let dpiHeight: Double?
    let hasAlpha: Bool?
    let byteCount: Int

    static func inspect(
        _ data: Data,
        formatHint: String? = nil
    ) throws -> ImageMetadata {
        if formatHint?.lowercased() == "svg" {
            let raster = try ImageRaster.decode(data, formatHint: formatHint)
            return ImageMetadata(
                formatIdentifier: "public.svg-image",
                width: raster.width,
                height: raster.height,
                depth: nil,
                colorModel: "RGB",
                profileName: nil,
                dpiWidth: nil,
                dpiHeight: nil,
                hasAlpha: true,
                byteCount: data.count)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw ImageComparisonError.cannotDecode
        }
        let image = CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        let alpha: Bool? = image.map {
            switch $0.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: false
            default: true
            }
        }
        return ImageMetadata(
            formatIdentifier: (CGImageSourceGetType(source) as String?) ??
                (formatHint.map { "public.\($0.lowercased())" } ?? "public.image"),
            width: width,
            height: height,
            depth: (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue,
            colorModel: properties[kCGImagePropertyColorModel] as? String,
            profileName: properties[kCGImagePropertyProfileName] as? String,
            dpiWidth: (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue,
            dpiHeight: (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue,
            hasAlpha: alpha,
            byteCount: data.count)
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

nonisolated struct ImageComparisonChannels: OptionSet, Equatable, Sendable {
    let rawValue: UInt8
    static let red = Self(rawValue: 1 << 0)
    static let green = Self(rawValue: 1 << 1)
    static let blue = Self(rawValue: 1 << 2)
    static let alpha = Self(rawValue: 1 << 3)
    static let rgb: Self = [.red, .green, .blue]
    static let all: Self = [.red, .green, .blue, .alpha]
}

nonisolated enum ImageDifferenceRendering: String, CaseIterable, Equatable, Sendable {
    case absolute
    case proportional
}

nonisolated struct ImageDifferenceColor: Equatable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    static let red = Self(red: 255, green: 0, blue: 0, alpha: 255)
    static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)
}

nonisolated struct ImageComparisonOptions: Equatable, Sendable {
    var threshold: UInt8 = 0
    var channels: ImageComparisonChannels = .all
    var rightOffsetX = 0
    var rightOffsetY = 0
    var rendering: ImageDifferenceRendering = .proportional
    var differingColor: ImageDifferenceColor = .red
    var identicalColor: ImageDifferenceColor = .clear
}

nonisolated enum ImageComparisonEngine {
    static func compare(left: ImageRaster, right: ImageRaster) -> ImageDifferenceResult {
        compare(left: left, right: right, options: ImageComparisonOptions())
    }

    static func compare(
        left: ImageRaster,
        right: ImageRaster,
        options: ImageComparisonOptions
    ) -> ImageDifferenceResult {
        let minimumX = min(0, options.rightOffsetX)
        let minimumY = min(0, options.rightOffsetY)
        let maximumX = max(left.width, options.rightOffsetX + right.width)
        let maximumY = max(left.height, options.rightOffsetY + right.height)
        let width = maximumX - minimumX
        let height = maximumY - minimumY
        let totalPixels = width * height
        var heatmap = Data(count: totalPixels * 4)
        var differingPixels = 0
        var differenceSum: UInt64 = 0
        var maximumDifference: UInt8 = 0
        let selectedChannelCount = options.channels.rawValue.nonzeroBitCount

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
                            let worldX = x + minimumX
                            let worldY = y + minimumY
                            let rightX = worldX - options.rightOffsetX
                            let rightY = worldY - options.rightOffsetY
                            let isInsideLeft = worldX >= 0 && worldY >= 0 && worldX < left.width && worldY < left.height
                            let isInsideRight = rightX >= 0 && rightY >= 0 && rightX < right.width && rightY < right.height
                            if isInsideLeft && isInsideRight {
                                let leftOffset = (worldY * left.width + worldX) * 4
                                let rightOffset = (rightY * right.width + rightX) * 4
                                for channel in 0..<4 {
                                    let channelFlag = ImageComparisonChannels(rawValue: 1 << channel)
                                    guard options.channels.contains(channelFlag) else { continue }
                                    let a = lhs[leftOffset + channel]
                                    let b = rhs[rightOffset + channel]
                                    let difference = a > b ? a - b : b - a
                                    pixelMaximum = max(pixelMaximum, difference)
                                    differenceSum += UInt64(difference)
                                }
                            } else {
                                if selectedChannelCount > 0 { pixelMaximum = 255 }
                                differenceSum += UInt64(255 * selectedChannelCount)
                            }
                            if pixelMaximum <= options.threshold { pixelMaximum = 0 }
                            if pixelMaximum > 0 { differingPixels += 1 }
                            maximumDifference = max(maximumDifference, pixelMaximum)
                            let color = pixelMaximum > 0 ? options.differingColor : options.identicalColor
                            let intensity: UInt8 = if pixelMaximum == 0 || options.rendering == .absolute {
                                255
                            } else {
                                pixelMaximum
                            }
                            output[outputOffset] = color.red
                            output[outputOffset + 1] = color.green
                            output[outputOffset + 2] = color.blue
                            output[outputOffset + 3] = UInt8(
                                min(255, Int(color.alpha) * Int(intensity) / 255))
                        }
                    }
                }
            }
        }

        let denominator = max(Double(totalPixels * selectedChannelCount) * 255.0, 1.0)
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

nonisolated enum ImageAlignmentEngine {
    static func visionTranslation(left: ImageRaster, right: ImageRaster) throws -> (x: Int, y: Int) {
        guard let leftImage = cgImage(left), let rightImage = cgImage(right) else {
            throw ImageComparisonError.invalidRaster
        }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: rightImage)
        let handler = VNImageRequestHandler(cgImage: leftImage)
        try handler.perform([request])
        guard let result = request.results?.first else { throw ImageComparisonError.cannotDecode }
        return (Int(result.alignmentTransform.tx.rounded()),
                Int(result.alignmentTransform.ty.rounded()))
    }

    /// Finds a small translation using a bounded, sampled RGB mean-absolute-error
    /// search. This is entirely local and caps work independently of image size.
    static func bestTranslation(
        left: ImageRaster,
        right: ImageRaster,
        maximumOffset: Int = 32,
        maximumSamples: Int = 2_000_000
    ) -> (x: Int, y: Int) {
        let limit = min(max(maximumOffset, 0), 128)
        let area = max(min(left.width, right.width) * min(left.height, right.height), 1)
        let candidateCount = (limit * 2 + 1) * (limit * 2 + 1)
        let samplesPerCandidate = max(maximumSamples / max(candidateCount, 1), 16)
        let stride = max(Int(sqrt(Double(area) / Double(samplesPerCandidate))), 1)
        var best = (x: 0, y: 0, score: UInt64.max, count: 0)
        left.rgba.withUnsafeBytes { leftBytes in
            right.rgba.withUnsafeBytes { rightBytes in
                let lhs = leftBytes.bindMemory(to: UInt8.self)
                let rhs = rightBytes.bindMemory(to: UInt8.self)
                for yOffset in -limit...limit {
                    for xOffset in -limit...limit {
                        var score: UInt64 = 0
                        var count = 0
                        var y = max(0, yOffset)
                        let endY = min(left.height, right.height + yOffset)
                        while y < endY {
                            var x = max(0, xOffset)
                            let endX = min(left.width, right.width + xOffset)
                            while x < endX {
                                let lo = (y * left.width + x) * 4
                                let ro = ((y - yOffset) * right.width + (x - xOffset)) * 4
                                for channel in 0..<3 {
                                    let a = lhs[lo + channel], b = rhs[ro + channel]
                                    score += UInt64(a > b ? a - b : b - a)
                                }
                                count += 1
                                x += stride
                            }
                            y += stride
                        }
                        guard count > 0 else { continue }
                        // Compare normalized scores without floating point.
                        if best.count == 0 || score * UInt64(best.count) < best.score * UInt64(count) {
                            best = (xOffset, yOffset, score, count)
                        }
                    }
                }
            }
        }
        return (best.x, best.y)
    }

    private static func cgImage(_ raster: ImageRaster) -> CGImage? {
        guard let provider = CGDataProvider(data: raster.rgba as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: raster.width * 4, space: colorSpace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                        .union(.byteOrder32Big), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
