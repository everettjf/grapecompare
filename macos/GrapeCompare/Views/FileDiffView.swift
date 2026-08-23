import SwiftUI
import UniformTypeIdentifiers

/// 文件 diff 视图：左右并排、行级 + 行内高亮、差异导航
struct FileDiffView: View {
    @Environment(AppState.self) private var state
    @State private var currentDiff = 0
    @State private var currentHunk = 0
    @State private var scrollRequest: ScrollRequest?
    @State private var scrollNonce = 0
    @State private var searchQuery = ""
    @State private var goToLine = ""
    @State private var wrapsLines = false
    @State private var exportsPatch = false
    @State private var patchDocument = TextPatchDocument(text: "")
    @State private var patchText = ""
    @State private var exportError: String?
    @State private var pendingNavigation: PendingNavigation?
    @State private var editsCustomFilters = false

    private enum PendingNavigation {
        case back, swap
    }

    private struct ScrollRequest: Equatable {
        let row: Int
        let nonce: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.fileDiff?.isBinary == false, state.fileDiff?.isTooLarge == false {
                Divider()
                textActionBar
            }
            Divider()
            content
        }
        .modifier(TextPatchExportModifier(
            isPresented: $exportsPatch,
            legacyDocument: patchDocument,
            text: patchText,
            contentType: .plainText,
            defaultFilename: "changes.patch") { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
                }
            })
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .confirmationDialog(
            "Save changes before leaving?",
            isPresented: Binding(
                get: { pendingNavigation != nil },
                set: { if !$0 { pendingNavigation = nil } }),
            titleVisibility: .visible
        ) {
            Button("Save and Continue") {
                let action = pendingNavigation
                state.saveOutput()
                if !state.outputIsDirty { performNavigation(action) }
                pendingNavigation = nil
            }
            Button("Discard Changes", role: .destructive) {
                let action = pendingNavigation
                state.resetOutput()
                performNavigation(action)
                pendingNavigation = nil
            }
            Button("Cancel", role: .cancel) { pendingNavigation = nil }
        } message: {
            Text("The editable output contains changes that have not been saved.")
        }
        .sheet(isPresented: $editsCustomFilters) {
            TextFilterEditor(patterns: state.textComparisonOptions.customFilterPatterns) { patterns in
                var options = state.textComparisonOptions
                options.customFilterPatterns = patterns
                state.updateTextComparisonOptions(options)
                editsCustomFilters = false
            } onCancel: {
                editsCustomFilters = false
            }
        }
    }

    private var textActionBar: some View {
        HStack(spacing: 8) {
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 180, maxWidth: 240)
                .onSubmit { jumpToSearch(1) }
                .accessibilityLabel("Search both files")
            Button { jumpToSearch(-1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(searchQuery.isEmpty)
            .help("Previous search result")
            Button { jumpToSearch(1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(searchQuery.isEmpty)
            .help("Next search result")

            TextField("Line", text: $goToLine)
                .textFieldStyle(.roundedBorder)
                .frame(width: 74)
                .onSubmit { jumpToLine() }
                .accessibilityLabel("Go to line")

            Menu {
                Picker("Whitespace", selection: whitespaceBinding) {
                    Text("Exact whitespace").tag(WhitespaceComparison.exact)
                    Text("Ignore whitespace changes").tag(WhitespaceComparison.ignoreChanges)
                    Text("Ignore all whitespace").tag(WhitespaceComparison.ignoreAll)
                }
                Toggle("Ignore case", isOn: ignoreCaseBinding)
                Toggle("Ignore line-ending format", isOn: ignoreLineEndingBinding)
                Toggle("Ignore final newline", isOn: ignoreFinalNewlineBinding)
                Divider()
                Toggle("Ignore C-style line comments", isOn: optionBinding(\.ignoreCStyleLineComments))
                Toggle("Ignore shell line comments", isOn: optionBinding(\.ignoreShellLineComments))
                Toggle("Ignore single-line HTML comments", isOn: optionBinding(\.ignoreHTMLComments))
                Divider()
                Toggle("Ignore timestamps", isOn: optionBinding(\.ignoreTimestamps))
                Toggle("Ignore UUIDs", isOn: optionBinding(\.ignoreUUIDs))
                Toggle("Ignore hexadecimal addresses", isOn: optionBinding(\.ignoreHexAddresses))
                Button("Custom Regular Expressions…") { editsCustomFilters = true }
            } label: {
                Label("Rules", systemImage: "slider.horizontal.3")
            }
            .disabled(state.outputIsDirty)

            Toggle(isOn: $wrapsLines) {
                Label("Wrap", systemImage: "arrow.turn.down.right")
            }
            .toggleStyle(.button)

            Spacer()

            if let comparison = state.textComparison, !comparison.hunks.isEmpty {
                Button { moveHunk(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous hunk")
                Text("Hunk \(min(currentHunk + 1, comparison.hunks.count))/\(comparison.hunks.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button { moveHunk(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next hunk")
                Button("Use Left") { acceptCurrentHunk(.left) }
                Button("Use Right") { acceptCurrentHunk(.right) }
            }

            Button {
                state.showOutput()
            } label: {
                Label("Output", systemImage: "square.and.pencil")
            }
            .disabled(state.rightTextSnapshot == nil)

            Button {
                do {
                    patchText = try state.makePatch()
                    patchDocument = TextPatchDocument(text: patchText)
                    exportsPatch = true
                } catch {
                    exportError = error.localizedDescription
                }
            } label: {
                Label("Patch", systemImage: "doc.badge.arrow.up")
            }
            .disabled(state.textComparison == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    // MARK: 顶部工具栏

    private var header: some View {
        HStack(spacing: 12) {
            Button { requestNavigation(.back) } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut(.cancelAction)

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(state.leftFileName).bold().lineLimit(1).truncationMode(.middle)
            }
            .layoutPriority(1)

            Button { requestNavigation(.swap) } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("Swap sides")

            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(state.rightFileName).bold().lineLimit(1).truncationMode(.middle)
            }
            .layoutPriority(1)

            Menu {
                Section("Left") {
                    Button("Open in Default Editor") { state.openComparedFileExternally(left: true) }
                        .disabled(state.diffLeftURL == nil)
                    Button("Reveal in Finder") { state.revealComparedFileInFinder(left: true) }
                        .disabled(state.diffLeftURL == nil)
                }
                Section("Right") {
                    Button("Open in Default Editor") { state.openComparedFileExternally(left: false) }
                        .disabled(state.diffRightURL == nil)
                    Button("Reveal in Finder") { state.revealComparedFileInFinder(left: false) }
                        .disabled(state.diffRightURL == nil)
                }
            } label: {
                Label("External Editor", systemImage: "arrow.up.forward.app")
            }

            Spacer()

            if let r = state.fileDiff, !r.identical, !r.isBinary {
                Text("+\(r.addedCount)").foregroundStyle(.green).font(.callout).bold()
                Text("−\(r.removedCount)").foregroundStyle(.red).font(.callout).bold()
                Text("~\(r.modifiedCount)").foregroundStyle(.orange).font(.callout).bold()
                if r.finalNewlineDiffers {
                    Text("↵ final newline differs")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Text("· \(r.differenceCount) differing rows")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Button { jumpToDiff(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(r.differenceCount == 0)
                        .help("Previous difference")
                        .keyboardShortcut(.upArrow, modifiers: [.command])
                    Text(r.differenceCount == 0 ? "0/0" : "\(min(currentDiff + 1, r.differenceCount))/\(r.differenceCount)")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(minWidth: 44)
                    Button { jumpToDiff(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(r.differenceCount == 0)
                        .help("Next difference")
                        .keyboardShortcut(.downArrow, modifiers: [.command])
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if state.outputVisible, state.rightTextSnapshot != nil {
            VSplitView {
                comparisonContent
                    .frame(minHeight: 220)
                outputEditor
                    .frame(minHeight: 150)
            }
        } else {
            comparisonContent
        }
    }

    @ViewBuilder
    private var comparisonContent: some View {
        if let imageComparison = state.imageComparison {
            ImageComparisonView(
                leftURL: state.diffLeftURL,
                rightURL: state.diffRightURL,
                result: imageComparison)
        } else if let structuredDifferences = state.structuredDifferences {
            StructuredComparisonView(differences: structuredDifferences)
        } else if let structuredError = state.structuredError {
            ContentUnavailableView(
                "Invalid Structured Document",
                systemImage: "curlybraces.square",
                description: Text(structuredError))
        } else if state.isComparingFile {
            VStack(spacing: 12) {
                ProgressView()
                Text("Comparing…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = state.fileError {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Failed to read file: \(error)")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let r = state.fileDiff {
            if r.identical {
                placeholder(icon: "checkmark.seal.fill", text: "Files are identical", color: .green)
            } else if r.isBinary {
                placeholder(icon: "doc.questionmark", text: "Binary files differ; cannot show a text diff", color: .orange)
            } else if r.isTooLarge {
                placeholder(
                    icon: "doc.badge.ellipsis",
                    text: "Text diff is not rendered because a file exceeds 256 MB",
                    color: .orange)
            } else if r.rows.isEmpty, r.leftMissing || r.rightMissing {
                placeholder(
                    icon: "doc.badge.minus",
                    text: r.leftMissing
                        ? "The left file is missing; the right file is empty"
                        : "The right file is missing; the left file is empty",
                    color: .orange)
            } else {
                diffTable(r)
            }
        }
    }

    private var outputEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Editable Output", systemImage: "square.and.pencil")
                    .font(.headline)
                if state.outputIsDirty {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Reset") { state.resetOutput() }
                    .disabled(!state.outputIsDirty)
                Button("Save Right") { state.saveOutput() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!state.outputIsDirty)
                Button { state.outputVisible = false } label: {
                    Image(systemName: "xmark")
                }
                .help("Hide output")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            TextEditor(text: Binding(
                get: { state.outputText },
                set: { state.updateOutputText($0) }
            ))
            .font(Theme.mono)
            .accessibilityLabel("Editable comparison output")
            if let error = state.outputError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
        }
    }

    private func placeholder(
        icon: String,
        text: LocalizedStringResource,
        color: Color
    ) -> some View {
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
                let viewportColumnWidth = max(0, (geo.size.width - 1) / 2)
                let contentColumnWidth = wrapsLines
                    ? viewportColumnWidth
                    : max(
                        viewportColumnWidth,
                        min(CGFloat(r.maxLineLength) * 7.3 + 60, 80_000))
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(spacing: 0) {
                            ForEach(r.rows) { row in
                                DiffRowView(
                                    row: row,
                                    columnWidth: contentColumnWidth,
                                    wrapsLines: wrapsLines,
                                    searchQuery: searchQuery,
                                    fileExtension: state.diffRightURL?.pathExtension.lowercased() ?? ""
                                )
                            }
                        }
                        .frame(
                            width: contentColumnWidth * 2 + 1,
                            alignment: .leading)
                    }
                    .onChange(of: scrollRequest) {
                        if let target = scrollRequest {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(target.row, anchor: .center)
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
        scrollNonce &+= 1
        scrollRequest = ScrollRequest(
            row: r.differenceRowIndices[currentDiff],
            nonce: scrollNonce)
    }

    private func jumpToSearch(_ delta: Int) {
        guard let result = state.fileDiff, !searchQuery.isEmpty else { return }
        let matches = result.rows.indices.filter { index in
            let row = result.rows[index]
            return contains(row.left?.text, query: searchQuery) ||
                contains(row.right?.text, query: searchQuery)
        }
        guard !matches.isEmpty else { return }
        let currentRow = scrollRequest?.row ?? -1
        let target: Int
        if delta > 0 {
            target = matches.first(where: { $0 > currentRow }) ?? matches[0]
        } else {
            target = matches.last(where: { $0 < currentRow }) ?? matches[matches.count - 1]
        }
        requestScroll(to: target)
    }

    private func jumpToLine() {
        guard let result = state.fileDiff else { return }
        let value = goToLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = value.first.map { String($0).uppercased() }
        let digits = (prefix == "L" || prefix == "R" || prefix == "O")
            ? String(value.dropFirst()) : value
        guard let line = Int(digits), line > 0 else { return }
        if prefix == "O" {
            requestScroll(to: min(line - 1, max(result.rows.count - 1, 0)))
            return
        }
        if let index = result.rows.firstIndex(where: { row in
            prefix == "R" ? row.right?.number == line : row.left?.number == line
        }) {
            requestScroll(to: index)
        }
    }

    private func requestScroll(to row: Int) {
        scrollNonce &+= 1
        scrollRequest = ScrollRequest(row: row, nonce: scrollNonce)
    }

    private func contains(_ text: String?, query: String) -> Bool {
        text?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private func moveHunk(_ delta: Int) {
        guard let count = state.textComparison?.hunks.count, count > 0 else { return }
        currentHunk = (currentHunk + delta + count) % count
        if let hunk = state.textComparison?.hunks[currentHunk],
           let row = state.fileDiff?.rows.firstIndex(where: {
               $0.left?.number == hunk.leftRange.lowerBound + 1 ||
               $0.right?.number == hunk.rightRange.lowerBound + 1
           }) {
            requestScroll(to: row)
        }
    }

    private func acceptCurrentHunk(_ side: TextSide) {
        guard let hunks = state.textComparison?.hunks, !hunks.isEmpty else { return }
        currentHunk = min(currentHunk, hunks.count - 1)
        state.accept(side, hunkID: hunks[currentHunk].id)
    }

    private func requestNavigation(_ action: PendingNavigation) {
        if state.outputIsDirty {
            pendingNavigation = action
        } else {
            performNavigation(action)
        }
    }

    private func performNavigation(_ action: PendingNavigation?) {
        switch action {
        case .back: state.backFromDiff()
        case .swap: state.swapDiffSides()
        case nil: break
        }
    }

    private var whitespaceBinding: Binding<WhitespaceComparison> {
        Binding(
            get: { state.textComparisonOptions.whitespace },
            set: {
                var options = state.textComparisonOptions
                options.whitespace = $0
                state.updateTextComparisonOptions(options)
            })
    }

    private var ignoreCaseBinding: Binding<Bool> {
        optionBinding(\.ignoreCase)
    }

    private var ignoreLineEndingBinding: Binding<Bool> {
        optionBinding(\.ignoreLineEndingFormat)
    }

    private var ignoreFinalNewlineBinding: Binding<Bool> {
        optionBinding(\.ignoreFinalNewline)
    }

    private func optionBinding(_ keyPath: WritableKeyPath<TextComparisonOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { state.textComparisonOptions[keyPath: keyPath] },
            set: {
                var options = state.textComparisonOptions
                options[keyPath: keyPath] = $0
                state.updateTextComparisonOptions(options)
            })
    }
}

private struct TextFilterEditor: View {
    @State private var patternText: String
    @State private var invalidPatterns: [String] = []
    let onSave: ([String]) -> Void
    let onCancel: () -> Void

    init(
        patterns: [String],
        onSave: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _patternText = State(initialValue: patterns.joined(separator: "\n"))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Text Filters").font(.title2.bold())
            Text("Enter one regular expression per line. Matching text is replaced with the same comparison-only placeholder; source files are never modified.")
                .foregroundStyle(.secondary)
            TextEditor(text: $patternText)
                .font(.body.monospaced())
                .frame(minWidth: 560, minHeight: 220)
                .border(invalidPatterns.isEmpty ? Color.secondary.opacity(0.35) : .red)
                .accessibilityLabel("Custom regular expressions")
            if !invalidPatterns.isEmpty {
                Text("Invalid regular expression: \(invalidPatterns.joined(separator: ", "))")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Clear All") { patternText = "" }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save Filters") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func save() {
        let patterns = patternText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        invalidPatterns = TextComparisonEngine.invalidFilterPatterns(patterns)
        if invalidPatterns.isEmpty { onSave(patterns) }
    }
}

/// 并排 diff 中的一行
struct DiffRowView: View {
    let row: DiffRow
    let columnWidth: CGFloat
    let wrapsLines: Bool
    let searchQuery: String
    let fileExtension: String

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
                    .fixedSize(horizontal: !wrapsLines, vertical: wrapsLines)
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
        applySyntaxHighlighting(to: &s, source: side.text)
        if let r = side.changedRange, let ar = Range(r, in: s) {
            s[ar].backgroundColor = isLeft ? Theme.removedHighlight : Theme.addedHighlight
        }
        if !searchQuery.isEmpty {
            var searchStart = side.text.startIndex
            while searchStart < side.text.endIndex,
                  let range = side.text.range(
                    of: searchQuery,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<side.text.endIndex),
                  let attributedRange = Range(range, in: s) {
                s[attributedRange].backgroundColor = .yellow.opacity(0.65)
                searchStart = range.upperBound
            }
        }
        return s
    }

    private func applySyntaxHighlighting(to attributed: inout AttributedString, source: String) {
        let codeExtensions: Set<String> = [
            "swift", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "java",
            "kt", "kts", "c", "h", "cc", "cpp", "hpp", "cs", "sh", "zsh", "bash",
            "json", "yaml", "yml", "toml", "xml", "html", "css"
        ]
        guard codeExtensions.contains(fileExtension) else { return }
        let keywords: Set<String> = [
            "actor", "as", "async", "await", "break", "case", "catch", "class", "const",
            "continue", "default", "defer", "do", "else", "enum", "export", "extends",
            "false", "final", "for", "from", "func", "function", "guard", "if", "import",
            "in", "interface", "let", "nil", "null", "private", "protocol", "public",
            "return", "static", "struct", "switch", "throw", "throws", "true", "try",
            "typealias", "var", "while"
        ]
        var result = attributed
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .byWords) { word, range, _, _ in
            guard let word, keywords.contains(word), let target = Range(range, in: result) else { return }
            result[target].foregroundColor = .systemPurple
        }
        if let comment = source.range(of: "//"),
           let target = Range(comment.lowerBound..<source.endIndex, in: result) {
            result[target].foregroundColor = .systemGreen
        } else if source.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                  let target = Range(source.startIndex..<source.endIndex, in: result) {
            result[target].foregroundColor = .systemGreen
        }
        attributed = result
    }
}
