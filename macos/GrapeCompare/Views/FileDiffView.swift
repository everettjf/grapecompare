import SwiftUI

/// 文件 diff 视图：左右并排、行级 + 行内高亮、差异导航
struct FileDiffView: View {
    @EnvironmentObject var state: AppState
    @State private var currentDiff = 0
    @State private var scrollRequest: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: 顶部工具栏

    private var header: some View {
        HStack(spacing: 12) {
            Button { state.backFromDiff() } label: {
                Label("Back", systemImage: "chevron.left")
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(state.leftFileName).bold().lineLimit(1).truncationMode(.middle)
            }
            .layoutPriority(1)

            Button { state.swapDiffSides() } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap sides")

            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(state.rightFileName).bold().lineLimit(1).truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer()

            if let r = state.fileDiff, !r.identical, !r.isBinary {
                Text("+\(r.addedCount)").foregroundStyle(.green).font(.callout).bold()
                Text("−\(r.removedCount)").foregroundStyle(.red).font(.callout).bold()
                Text("~\(r.modifiedCount)").foregroundStyle(.orange).font(.callout).bold()
                Text("· \(r.differenceCount) differing rows")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button { jumpToDiff(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(r.differenceCount == 0)
                        .help("Previous difference")
                    Text(r.differenceCount == 0 ? "0/0" : "\(min(currentDiff + 1, r.differenceCount))/\(r.differenceCount)")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(minWidth: 44)
                    Button { jumpToDiff(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(r.differenceCount == 0)
                        .help("Next difference")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if state.isComparing {
            VStack(spacing: 12) {
                ProgressView()
                Text("Comparing…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.fileError {
            placeholder(icon: "exclamationmark.triangle", text: "Failed to read file: \(error)", color: .orange)
        } else if let r = state.fileDiff {
            if r.identical {
                placeholder(icon: "checkmark.seal.fill", text: "Files are identical", color: .green)
            } else if r.isBinary {
                placeholder(icon: "doc.questionmark", text: "Binary files differ; cannot show a text diff", color: .orange)
            } else {
                diffTable(r)
            }
        }
    }

    private func placeholder(icon: String, text: String, color: Color) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(color)
            Text(text)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diffTable(_ r: FileDiffResult) -> some View {
        VStack(spacing: 0) {
            // 列头：两侧完整路径
            HStack(spacing: 0) {
                columnHeader(state.diffLeftURL)
                Rectangle().fill(Theme.gutterDivider).frame(width: 1)
                columnHeader(state.diffRightURL)
            }
            // Rectangle 分隔线在垂直方向是弹性的，不锁死的话 VStack 会把多余空间均分给列头
            .fixedSize(horizontal: false, vertical: true)
            Divider()

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(r.rows) { row in
                                DiffRowView(
                                    row: row,
                                    columnWidth: max(0, (geo.size.width - 1) / 2)
                                )
                            }
                        }
                        .frame(width: geo.size.width, alignment: .leading)
                    }
                    .onChange(of: scrollRequest) {
                        if let target = scrollRequest {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                    .onAppear {
                        // 仅标记当前差异位置，不自动滚动——短文件居中滚动会把内容推歪
                        currentDiff = 0
                    }
                }
            }
        }
    }

    private func columnHeader(_ url: URL?) -> some View {
        Text(url.map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath } ?? "(Missing)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
    }

    // MARK: 差异导航

    private func jumpToDiff(_ delta: Int) {
        guard let r = state.fileDiff, r.differenceCount > 0 else { return }
        currentDiff = (currentDiff + delta + r.differenceCount) % r.differenceCount
        scrollRequest = r.differenceRowIndices[currentDiff]
    }
}

/// 并排 diff 中的一行
struct DiffRowView: View {
    let row: DiffRow
    let columnWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            sideView(row.left, isLeft: true)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
            Rectangle().fill(Theme.gutterDivider).frame(width: 1)
            sideView(row.right, isLeft: false)
                .frame(width: columnWidth, alignment: .leading)
                .clipped()
        }
        .frame(width: columnWidth * 2 + 1, alignment: .leading)
        .font(Theme.mono)
    }

    @ViewBuilder
    private func sideView(_ side: DiffRow.Side?, isLeft: Bool) -> some View {
        HStack(spacing: 0) {
            Text(side.map { String($0.number) } ?? "")
                .font(Theme.monoSmall)
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 10)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.03))
            if let side {
                Text(highlighted(side, isLeft: isLeft))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .background(backgroundColor(isLeft: isLeft))
    }

    private func backgroundColor(isLeft: Bool) -> Color {
        switch row.kind {
        case .equal: return .clear
        case .added: return isLeft ? Theme.emptyBg : Theme.addedBg
        case .removed: return isLeft ? Theme.removedBg : Theme.emptyBg
        case .modified: return isLeft ? Theme.modifiedLeftBg : Theme.modifiedRightBg
        }
    }

    /// modified 行中真正不同的字符段加深高亮
    private func highlighted(_ side: DiffRow.Side, isLeft: Bool) -> AttributedString {
        var s = AttributedString(side.text)
        if let r = side.changedRange, let ar = Range(r, in: s) {
            s[ar].backgroundColor = isLeft ? Theme.removedHighlight : Theme.addedHighlight
        }
        return s
    }
}
