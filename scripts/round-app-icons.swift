#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: round-app-icons.swift <png> [...]\n".utf8))
    exit(64)
}

for argument in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: argument)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Unable to read \(argument)")
    }

    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Unable to create a bitmap context for \(argument)")
    }

    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let radius = CGFloat(min(width, height)) * 0.20
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
    context.clip()
    context.interpolationQuality = .none
    context.draw(image, in: bounds)

    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else {
        fatalError("Unable to prepare \(argument) for writing")
    }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Unable to write \(argument)")
    }
}
