import AppKit
import SwiftUI

struct ImageComparisonView: View {
    @Environment(AppState.self) private var state
    @State private var savedPairKey = ""
    enum Mode: String, CaseIterable, Identifiable {
        case twoUp, oneUp, split, blink, difference
        var id: Self { self }
        var title: LocalizedStringResource {
            switch self {
            case .twoUp: "Two-Up"
            case .oneUp: "One-Up"
            case .split: "Split"
            case .blink: "Blink"
            case .difference: "Difference"
            }
        }
    }

    let leftURL: URL?
    let rightURL: URL?
    let result: ImageDifferenceResult
    @State private var mode = Mode.twoUp
    @State private var showRight = false
    @State private var zoom = 1.0
    @State private var pan = CGSize.zero
    @GestureState private var dragTranslation = CGSize.zero
    @State private var split = 0.5
    @State private var threshold = 0.0
    @State private var channels = ImageComparisonChannels.all
    @State private var differenceRendering = ImageDifferenceRendering.proportional
    @State private var differingColor = Color.red
    @State private var identicalColor = Color.clear
    @State private var offsetX = 0
    @State private var offsetY = 0
    @State private var leftRaster: ImageRaster?
    @State private var rightRaster: ImageRaster?
    @State private var leftImage: NSImage?
    @State private var rightImage: NSImage?
    @State private var pixel: PixelInspection?
    @State private var lockedPixel: PixelInspection?
    @State private var leftMetadata: ImageMetadata?
    @State private var rightMetadata: ImageMetadata?
    @State private var showsMetadata = false
    @State private var loadError: String?
    @State private var canvasSize = CGSize.zero
    @State private var computedResult: ImageDifferenceResult?
    @State private var isComputingDifference = false
    @State private var differenceGeneration = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentResult: ImageDifferenceResult {
        computedResult ?? result
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content.clipped().overlay(alignment: .topTrailing) { navigator.padding(12) }
            Divider()
            status
        }
        .task(id: pairKey) {
            restoreReading()
            await load()
        }
        .onDisappear { saveReading() }
        .task(id: differenceOptionsKey) {
            try? await Task.sleep(for: .milliseconds(80))
            await recomputeDifference()
        }
        .task(id: mode) {
            guard mode == .blink, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { showRight.toggle() }
            }
        }
    }

    private var pairKey: String {
        ComparisonReadingStore.key(kind: "images", left: leftURL, right: rightURL)
    }

    private func saveReading() {
        guard !savedPairKey.isEmpty else { return }
        var value = ComparisonReadingState()
        value.image = ImageReadingState(mode: mode.rawValue, zoom: zoom,
            panX: pan.width, panY: pan.height, split: split, offsetX: offsetX, offsetY: offsetY,
            threshold: threshold, channels: channels.rawValue, rendering: differenceRendering.rawValue)
        state.readingStore.save(value, for: savedPairKey)
    }

    private func restoreReading() {
        if savedPairKey == pairKey { return }
        saveReading()
        savedPairKey = pairKey
        differenceGeneration = UUID()
        leftRaster = nil; rightRaster = nil
        leftImage = nil; rightImage = nil
        leftMetadata = nil; rightMetadata = nil
        computedResult = nil; loadError = nil
        isComputingDifference = false
        let value = (state.readingStore.read(pairKey)?.image ?? ImageReadingState()).validated()
        mode = Mode(rawValue: value.mode) ?? .twoUp
        zoom = value.zoom
        pan = CGSize(width: value.panX, height: value.panY)
        split = value.split
        offsetX = value.offsetX
        offsetY = value.offsetY
        threshold = value.threshold
        channels = ImageComparisonChannels(rawValue: value.channels)
        differenceRendering = ImageDifferenceRendering(rawValue: value.rendering) ?? .proportional
        pixel = nil
        lockedPixel = nil
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { modeControls; zoomControls }
                VStack(alignment: .leading, spacing: 8) { modeControls; zoomControls }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { inspectionControls; thresholdControls }
                VStack(alignment: .leading, spacing: 8) { inspectionControls; thresholdControls }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.small).padding(10)
    }

    private var modeControls: some View {
            Picker("Image display", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 430)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { zoom = max(0.1, zoom / 1.25) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                .labelStyle(.iconOnly)
                .keyboardShortcut("-", modifiers: .command)
            Slider(value: $zoom, in: 0.1...8).frame(width: 90)
                .accessibilityLabel("Image zoom")
                .accessibilityValue(Text(zoom, format: .percent.precision(.fractionLength(0))))
            Button { zoom = min(8, zoom * 1.25) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                .labelStyle(.iconOnly)
                .keyboardShortcut("+", modifiers: .command)
            Button("Fit") { zoom = 1; pan = .zero }.keyboardShortcut("0", modifiers: .command)
            Button("Actual Pixels") { showActualPixels() }.keyboardShortcut("1", modifiers: .command)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var inspectionControls: some View {
        HStack(spacing: 8) {
            Menu("Channels") {
                channelButton("Red", .red); channelButton("Green", .green)
                channelButton("Blue", .blue); channelButton("Alpha", .alpha)
            }
            Menu("Difference Rendering") {
                Picker("Intensity", selection: $differenceRendering) {
                    Text("Absolute").tag(ImageDifferenceRendering.absolute)
                    Text("Proportional").tag(ImageDifferenceRendering.proportional)
                }
                Divider()
                ColorPicker("Different Pixels", selection: $differingColor, supportsOpacity: true)
                ColorPicker("Identical Pixels", selection: $identicalColor, supportsOpacity: true)
            }
            Menu("Align") {
                Stepper("Horizontal: \(offsetX) px", value: $offsetX, in: -10_000...10_000)
                Stepper("Vertical: \(offsetY) px", value: $offsetY, in: -10_000...10_000)
                Button("Auto Align Locally") { autoAlign() }
                Button("Reset Alignment") { offsetX = 0; offsetY = 0 }
            }
            Button("Image Inspector", systemImage: "info.circle") {
                showsMetadata.toggle()
            }
            .labelStyle(.iconOnly)
            .popover(isPresented: $showsMetadata) {
                ImageMetadataInspector(left: leftMetadata, right: rightMetadata)
                    .frame(width: 520)
                    .padding(16)
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var thresholdControls: some View {
        HStack(spacing: 8) {
            Text("Threshold")
            Slider(value: $threshold, in: 0...255, step: 1).frame(width: 90)
                .accessibilityLabel("Pixel difference threshold")
            Text(threshold, format: .number.precision(.fractionLength(0))).monospacedDigit()
            if isComputingDifference {
                ProgressView().controlSize(.small).accessibilityLabel("Updating image difference")
            }
        }.fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var content: some View {
        if let loadError {
            ContentUnavailableView("Unable to Load Image", systemImage: "photo.badge.exclamationmark",
                                   description: Text(loadError))
        } else {
            switch mode {
            case .twoUp:
                HSplitView {
                    canvas(leftImage, leftRaster, "Left image")
                    canvas(rightImage, rightRaster, "Right image")
                }
            case .oneUp:
                canvas(showRight ? rightImage : leftImage, showRight ? rightRaster : leftRaster,
                       showRight ? "Right image" : "Left image", aligned: showRight)
                    .overlay(alignment: .topLeading) {
                        Picker("Visible image", selection: $showRight) {
                            Text("Left").tag(false); Text("Right").tag(true)
                        }.pickerStyle(.segmented).frame(width: 120).padding()
                    }
            case .split:
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        transformed(rightImage, aligned: true)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        transformed(leftImage)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: proxy.size.width * split) }
                        Rectangle().fill(.white).frame(width: 1).offset(x: proxy.size.width * split)
                    }
                    .contentShape(.rect)
                    .gesture(DragGesture()
                        .updating($dragTranslation) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            pan = CGSize(width: pan.width + value.translation.width,
                                         height: pan.height + value.translation.height)
                        })
                    .overlay(alignment: .bottom) {
                        Slider(value: $split).frame(width: 280).padding().accessibilityLabel("Split position")
                    }
                    .onChange(of: proxy.size, initial: true) { _, size in canvasSize = size }
                }
            case .blink:
                canvas(showRight ? rightImage : leftImage, showRight ? rightRaster : leftRaster,
                       showRight ? "Right image" : "Left image", aligned: showRight)
            case .difference:
                canvas(makeImage(currentResult.heatmap), currentResult.heatmap, "Image difference heatmap")
            }
        }
    }

    private func canvas(
        _ image: NSImage?, _ raster: ImageRaster?, _ label: LocalizedStringResource,
        aligned: Bool = false
    ) -> some View {
        GeometryReader { proxy in
            ZStack {
                transformed(image, aligned: aligned)
                if let lockedPixel,
                   let point = samplePoint(lockedPixel, raster: raster, size: proxy.size, aligned: aligned) {
                    PixelCrosshair().position(point)
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        pan = CGSize(width: pan.width + value.translation.width,
                                     height: pan.height + value.translation.height)
                    })
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): pixel = raster.flatMap { inspect($0, point, proxy.size, aligned: aligned) }
                    case .ended: if lockedPixel == nil { pixel = nil }
                    }
                }.accessibilityLabel(Text(label))
                .onChange(of: proxy.size, initial: true) { _, size in canvasSize = size }
        }
    }

    @ViewBuilder private func transformed(_ image: NSImage?, aligned: Bool = false) -> some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                .scaleEffect(zoom)
                .offset(x: pan.width + dragTranslation.width + (aligned ? Double(offsetX) * zoom : 0),
                        y: pan.height + dragTranslation.height + (aligned ? Double(offsetY) * zoom : 0))
        } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
    }

    private var navigator: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let preview = mode == .difference ? makeImage(currentResult.heatmap) : leftImage {
                Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).frame(width: 120, height: 80)
                    .background(.black.opacity(0.5)).overlay(Rectangle().stroke(.white.opacity(0.8)))
            }
            if let sample = lockedPixel ?? pixel {
                Text(sample.summary)
                    .font(.caption2.monospaced()).padding(5).background(.regularMaterial, in: .rect(cornerRadius: 4))
                Button(lockedPixel == nil ? "Lock Pixel Sample" : "Unlock Pixel Sample") {
                    lockedPixel = lockedPixel == nil ? sample : nil
                }
                .controlSize(.mini)
            }
        }.accessibilityElement(children: .combine).accessibilityLabel("Image navigator and pixel inspector")
    }

    private var status: some View {
        let value = currentResult
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 4) {
            Text("Left: \(value.leftWidth)×\(value.leftHeight)")
            Text("Right: \(value.rightWidth)×\(value.rightHeight)")
            Text("\(value.differingPixelCount) / \(value.comparedPixelCount) pixels")
            Text(value.meanAbsoluteDifference, format: .percent.precision(.fractionLength(3)))
            Text("Zoom: \(zoom, format: .percent.precision(.fractionLength(0)))")
            Text("Maximum channel difference: \(value.maximumChannelDifference)")
            Text(value.identical ? "Images are identical" : "Images differ")
                .foregroundStyle(value.identical ? .green : .orange)
        }.font(.caption).padding(8)
    }

    private func channelButton(_ title: LocalizedStringResource, _ channel: ImageComparisonChannels) -> some View {
        Button {
            if channels.contains(channel) { channels.remove(channel) } else { channels.insert(channel) }
            if channels.isEmpty { channels = channel }
        } label: { Label(title, systemImage: channels.contains(channel) ? "checkmark.square" : "square") }
    }

    private func load() async {
        guard let leftURL, let rightURL else { return }
        let loaded = await Task.detached(priority: .userInitiated) {
            () -> Result<(ImageRaster, ImageRaster, ImageMetadata, ImageMetadata), Error> in
            Result {
                let leftData = try Data(contentsOf: leftURL, options: .mappedIfSafe)
                let rightData = try Data(contentsOf: rightURL, options: .mappedIfSafe)
                return (
                    try ImageRaster.decode(leftData, formatHint: leftURL.pathExtension),
                    try ImageRaster.decode(rightData, formatHint: rightURL.pathExtension),
                    try ImageMetadata.inspect(leftData, formatHint: leftURL.pathExtension),
                    try ImageMetadata.inspect(rightData, formatHint: rightURL.pathExtension))
            }
        }.value
        guard !Task.isCancelled else { return }
        switch loaded {
        case .success(let pair):
            leftRaster = pair.0; rightRaster = pair.1
            leftMetadata = pair.2; rightMetadata = pair.3
            leftImage = makeImage(pair.0); rightImage = makeImage(pair.1); loadError = nil
            await recomputeDifference()
        case .failure(let error): loadError = error.localizedDescription
        }
    }

    private func recomputeDifference() async {
        guard let leftRaster, let rightRaster else { return }
        let options = ImageComparisonOptions(
            threshold: UInt8(threshold), channels: channels,
            rightOffsetX: offsetX, rightOffsetY: offsetY,
            rendering: differenceRendering,
            differingColor: imageDifferenceColor(differingColor),
            identicalColor: imageDifferenceColor(identicalColor))
        let generation = UUID()
        differenceGeneration = generation
        isComputingDifference = true
        let value = await Task.detached(priority: .userInitiated) {
            ImageComparisonEngine.compare(left: leftRaster, right: rightRaster, options: options)
        }.value
        guard !Task.isCancelled, differenceGeneration == generation else { return }
        computedResult = value
        isComputingDifference = false
    }

    private func autoAlign() {
        guard let leftRaster, let rightRaster else { return }
        let key = savedPairKey
        Task {
            let alignment = await Task.detached(priority: .userInitiated) {
                (try? ImageAlignmentEngine.visionTranslation(left: leftRaster, right: rightRaster)) ??
                    ImageAlignmentEngine.bestTranslation(left: leftRaster, right: rightRaster)
            }.value
            guard savedPairKey == key else { return }
            offsetX = alignment.x
            offsetY = alignment.y
        }
    }

    private func showActualPixels() {
        guard let raster = leftRaster, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let fit = min(canvasSize.width / Double(raster.width), canvasSize.height / Double(raster.height))
        zoom = min(8, max(0.1, 1 / fit))
        pan = .zero
    }

    private func inspect(
        _ raster: ImageRaster, _ point: CGPoint, _ size: CGSize, aligned: Bool
    ) -> PixelInspection? {
        guard size.width > 0, size.height > 0, raster.width > 0, raster.height > 0 else { return nil }
        let fit = min(size.width / Double(raster.width), size.height / Double(raster.height))
        let width = Double(raster.width) * fit * zoom
        let height = Double(raster.height) * fit * zoom
        let originX = (size.width - width) / 2 + pan.width + dragTranslation.width +
            (aligned ? Double(offsetX) * zoom : 0)
        let originY = (size.height - height) / 2 + pan.height + dragTranslation.height +
            (aligned ? Double(offsetY) * zoom : 0)
        guard point.x >= originX, point.y >= originY,
              point.x < originX + width, point.y < originY + height else { return nil }
        let x = min(Int((point.x - originX) / width * Double(raster.width)), raster.width - 1)
        let y = min(Int((point.y - originY) / height * Double(raster.height)), raster.height - 1)
        let o = (y * raster.width + x) * 4
        return raster.rgba.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            return PixelInspection(x: x, y: y, r: p[o], g: p[o + 1], b: p[o + 2], a: p[o + 3])
        }
    }

    private var differenceOptionsKey: String {
        let changed = imageDifferenceColor(differingColor)
        let same = imageDifferenceColor(identicalColor)
        return "\(Int(threshold))|\(channels.rawValue)|\(offsetX)|\(offsetY)|" +
            "\(differenceRendering.rawValue)|\(changed)|\(same)"
    }

    private func imageDifferenceColor(_ color: Color) -> ImageDifferenceColor {
        let converted = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8(max(0, min(255, Int((value * 255).rounded()))))
        }
        return ImageDifferenceColor(
            red: byte(converted.redComponent), green: byte(converted.greenComponent),
            blue: byte(converted.blueComponent), alpha: byte(converted.alphaComponent))
    }

    private func samplePoint(
        _ sample: PixelInspection, raster: ImageRaster?, size: CGSize, aligned: Bool
    ) -> CGPoint? {
        guard let raster, raster.width > 0, raster.height > 0 else { return nil }
        let fit = min(size.width / Double(raster.width), size.height / Double(raster.height))
        let width = Double(raster.width) * fit * zoom
        let height = Double(raster.height) * fit * zoom
        return CGPoint(
            x: (size.width - width) / 2 + pan.width + dragTranslation.width +
                (aligned ? Double(offsetX) * zoom : 0) +
                (Double(sample.x) + 0.5) / Double(raster.width) * width,
            y: (size.height - height) / 2 + pan.height + dragTranslation.height +
                (aligned ? Double(offsetY) * zoom : 0) +
                (Double(sample.y) + 0.5) / Double(raster.height) * height)
    }

    private func makeImage(_ raster: ImageRaster) -> NSImage? {
        guard raster.width > 0, raster.height > 0,
              let provider = CGDataProvider(data: raster.rgba as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: raster.width, height: raster.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: raster.width * 4, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                                    .union(.byteOrder32Big), provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: raster.width, height: raster.height))
    }
}

private struct PixelCrosshair: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.white).frame(width: 17, height: 1)
            Rectangle().fill(.white).frame(width: 1, height: 17)
            Circle().stroke(.black, lineWidth: 1).frame(width: 9, height: 9)
        }
        .shadow(color: .black.opacity(0.8), radius: 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PixelInspection {
    let x: Int; let y: Int
    let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8

    var summary: String {
        let red = Double(r) / 255
        let green = Double(g) / 255
        let blue = Double(b) / 255
        let maximum = max(red, max(green, blue))
        let minimum = min(red, min(green, blue))
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum
        var hue = 0.0
        if delta > 0 {
            if maximum == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        let lab = Self.lab(red: red, green: green, blue: blue)
        return String(
            format: "x:%d y:%d  RGBA %d,%d,%d,%d  HSB %.0f°,%.0f%%,%.0f%%  Lab %.1f,%.1f,%.1f",
            x, y, r, g, b, a, hue, saturation * 100, maximum * 100, lab.0, lab.1, lab.2)
    }

    private static func lab(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
        let y = r * 0.2126 + g * 0.7152 + b * 0.0722
        let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
        func curve(_ value: Double) -> Double {
            value > 0.008856 ? pow(value, 1 / 3) : 7.787 * value + 16 / 116
        }
        let fx = curve(x), fy = curve(y), fz = curve(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}

private struct ImageMetadataInspector: View {
    let left: ImageMetadata?
    let right: ImageMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Image Inspector").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                metadataColumn("Left", left)
                Divider()
                metadataColumn("Right", right)
            }
        }
    }

    private func metadataColumn(_ title: LocalizedStringResource, _ metadata: ImageMetadata?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            if let metadata {
                LabeledContent("Format", value: metadata.formatIdentifier)
                LabeledContent("Dimensions", value: "\(metadata.width) × \(metadata.height)")
                LabeledContent("Encoded Size", value: ByteCountFormatter.string(
                    fromByteCount: Int64(metadata.byteCount), countStyle: .file))
                LabeledContent("Color Model", value: metadata.colorModel ?? "—")
                LabeledContent("Color Profile", value: metadata.profileName ?? "—")
                LabeledContent("Bit Depth", value: metadata.depth.map(String.init) ?? "—")
                LabeledContent("Alpha Channel", value: metadata.hasAlpha == true ? String(localized: "Yes") : String(localized: "No"))
                if let x = metadata.dpiWidth, let y = metadata.dpiHeight {
                    LabeledContent("Resolution", value: String(format: "%.0f × %.0f DPI", x, y))
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
