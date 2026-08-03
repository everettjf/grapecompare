import AppKit
import SwiftUI

struct ImageComparisonView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide
        case overlay
        case heatmap

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .sideBySide: "Side by Side"
            case .overlay: "Overlay"
            case .heatmap: "Difference Heatmap"
            }
        }
    }

    let leftURL: URL?
    let rightURL: URL?
    let result: ImageDifferenceResult
    @State private var mode: Mode = .sideBySide
    @State private var overlayOpacity = 0.5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Image display", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                if mode == .overlay {
                    Slider(value: $overlayOpacity, in: 0...1) {
                        Text("Right image opacity")
                    }
                    .frame(maxWidth: 220)
                }
                Spacer()
                Text("\(result.differingPixelCount) / \(result.comparedPixelCount) pixels")
                Text(result.meanAbsoluteDifference, format: .percent.precision(.fractionLength(3)))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            switch mode {
            case .sideBySide:
                HSplitView {
                    imagePane(url: leftURL, label: "Left image")
                    imagePane(url: rightURL, label: "Right image")
                }
            case .overlay:
                ZStack {
                    localImage(url: leftURL)
                    localImage(url: rightURL).opacity(overlayOpacity)
                }
                .padding()
            case .heatmap:
                if let image = nsImage(from: result.heatmap) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding()
                        .accessibilityLabel("Image difference heatmap")
                } else {
                    ContentUnavailableView("Unable to Load Image", systemImage: "photo.badge.exclamationmark")
                }
            }
            Divider()
            HStack(spacing: 18) {
                Text("Left: \(result.leftWidth)×\(result.leftHeight)")
                Text("Right: \(result.rightWidth)×\(result.rightHeight)")
                Text("Maximum channel difference: \(result.maximumChannelDifference)")
                Spacer()
                Text(result.identical ? "Images are identical" : "Images differ")
                    .foregroundStyle(result.identical ? .green : .orange)
            }
            .font(.caption)
            .padding(8)
        }
    }

    private func imagePane(url: URL?, label: LocalizedStringResource) -> some View {
        localImage(url: url)
            .padding()
            .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(label))
    }

    @ViewBuilder
    private func localImage(url: URL?) -> some View {
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else {
            ContentUnavailableView("Unable to Load Image", systemImage: "photo.badge.exclamationmark")
        }
    }

    private func nsImage(from raster: ImageRaster) -> NSImage? {
        guard let provider = CGDataProvider(data: raster.rgba as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raster.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: raster.width, height: raster.height))
    }
}
