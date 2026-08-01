import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 首页：选择比较模式并拖入/选择两侧的文件或文件夹
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("showDemoButton") private var showDemoButton = true

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 10) {
                Image("GrapeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .shadow(color: .green.opacity(0.35), radius: 12, y: 6)
                Text("GrapeCompare")
                    .font(.system(size: 32, weight: .bold))
                Text("Native, fast, and professional file & folder comparison")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 44)

            HStack(spacing: 24) {
                CompareCard(
                    title: "Compare Files",
                    icon: "doc.text.magnifyingglass",
                    description: "Side-by-side diff with line and in-line highlighting",
                    acceptsFolders: false,
                    left: $state.leftFileURL,
                    right: $state.rightFileURL,
                    action: state.startFileCompare)
                CompareCard(
                    title: "Compare Folders",
                    icon: "folder.badge.questionmark",
                    description: "Recursively compare folders to find added, missing, and modified files",
                    acceptsFolders: true,
                    left: $state.leftFolderURL,
                    right: $state.rightFolderURL,
                    action: state.startFolderCompare)
            }
            .padding(.horizontal, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if showDemoButton {
                Menu {
                    Button("Compare Swift Files", systemImage: "doc.text.magnifyingglass") {
                        state.loadFileDemo()
                    }
                    Button("Compare Swift Project Folders", systemImage: "folder.badge.questionmark") {
                        state.loadFolderDemo()
                    }
                } label: {
                    Label("Load Demo", systemImage: "sparkles")
                }
                .menuStyle(.button)
                .controlSize(.large)
                .padding(20)
            }
        }
        .alert("Unable to Load Demo", isPresented: Binding(
            get: { state.demoError != nil },
            set: { if !$0 { state.demoError = nil } }
        )) {
            Button("OK") { state.demoError = nil }
        } message: {
            Text(state.demoError ?? "Unknown error")
        }
    }
}

private struct CompareCard: View {
    let title: String
    let icon: String
    let description: String
    let acceptsFolders: Bool
    @Binding var left: URL?
    @Binding var right: URL?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title3).bold()
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                DropSlot(label: "Left", acceptsFolders: acceptsFolders, url: $left)
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.tertiary)
                DropSlot(label: "Right", acceptsFolders: acceptsFolders, url: $right)
            }

            Button("Compare", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(left == nil || right == nil)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

/// 拖放/点选槽位
struct DropSlot: View {
    let label: String
    let acceptsFolders: Bool
    @Binding var url: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 6) {
            if let url {
                Image(systemName: acceptsFolders ? "folder.fill" : "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                Text(url.lastPathComponent)
                    .font(.callout).bold()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Remove") { setURL(nil) }
                    .font(.caption)
                    .buttonStyle(.link)
            } else {
                Image(systemName: "arrow.down.doc")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("\(label): drop a \(acceptsFolders ? "folder" : "file") here")
                    .font(.caption)
                Text("or click to choose")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 116)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { item, _ in
                DispatchQueue.main.async {
                    guard let item else { return }
                    if self.acceptsFolders, !item.hasDirectoryPath { return }
                    self.setURL(item)
                }
            }
            return true
        }
    }

    /// 设置槽位 URL 并管理沙盒安全作用域访问。
    /// App Sandbox 下，拖放得来的 URL 是 security-scoped 的，必须先
    /// startAccessing 才能读取其内容（文件夹访问权覆盖其所有子项）。
    /// NSOpenPanel 返回的 URL 已获授权，startAccessing 会返回 false，无害。
    private func setURL(_ new: URL?) {
        guard new != url else { return }
        url?.stopAccessingSecurityScopedResource()
        if let new { _ = new.startAccessingSecurityScopedResource() }
        url = new
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !acceptsFolders
        panel.canChooseDirectories = acceptsFolders
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK {
            setURL(panel.url)
        }
    }
}
