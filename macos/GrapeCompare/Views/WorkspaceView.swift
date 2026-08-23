import SwiftUI

struct WorkspaceView: View {
    @Bindable var workspace: WorkspaceController
    @State private var pendingCloseID: WorkspaceController.Item.ID?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ContentView()
                .environment(workspace.selectedState)
                .id(workspace.selectedID)
        }
        .confirmationDialog(
            "Discard unsaved comparison output?",
            isPresented: Binding(
                get: { pendingCloseID != nil },
                set: { if !$0 { pendingCloseID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard and Close", role: .destructive) {
                if let pendingCloseID {
                    workspace.items.first(where: { $0.id == pendingCloseID })?.state.discardWorkspaceOutput()
                    workspace.close(pendingCloseID)
                }
                pendingCloseID = nil
            }
            Button("Cancel", role: .cancel) { pendingCloseID = nil }
        } message: {
            Text("Export or save the edited output before closing if you want to keep it.")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(workspace.items) { item in
                        HStack(spacing: 4) {
                            Button {
                                workspace.select(item.id)
                            } label: {
                                Label(item.state.workspaceTitle, systemImage: item.state.workspaceIcon)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 8)
                            .accessibilityAddTraits(
                                workspace.selectedID == item.id ? .isSelected : [])

                            Button {
                                requestClose(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .accessibilityLabel("Close \(item.state.workspaceTitle)")
                            }
                            .buttonStyle(.plain)
                            .disabled(item.state.workspaceIsBusy)
                            .padding(.trailing, 6)
                        }
                        .padding(.vertical, 6)
                        .background(
                            workspace.selectedID == item.id
                                ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: .rect(cornerRadius: 7))
                    }
                }
            }
            Button {
                workspace.addComparison()
            } label: {
                Image(systemName: "plus")
            }
            .help("New Comparison")
            .accessibilityLabel("New Comparison")
            if workspace.selectedState.screen != .home {
                Button {
                    workspace.selectedState.setLiveUpdatesEnabled(
                        !workspace.selectedState.liveUpdatesEnabled)
                } label: {
                    Image(systemName: liveUpdateSymbol)
                }
                .buttonStyle(.plain)
                .help(liveUpdateHelp)
                .accessibilityLabel(liveUpdateHelp)
                .accessibilityValue(
                    workspace.selectedState.liveUpdatesEnabled
                        ? String(localized: "Enabled")
                        : String(localized: "Disabled"))
                .contextMenu {
                    Toggle("Git live change notifications", isOn: Binding(
                        get: { workspace.selectedState.liveNotificationsEnabled },
                        set: { workspace.selectedState.setLiveNotificationsEnabled($0) }))
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(.bar)
    }

    private var liveUpdateSymbol: String {
        let state = workspace.selectedState
        if !state.liveUpdatesEnabled { return "bell.slash" }
        if state.liveUpdatePausedReason != nil { return "exclamationmark.triangle" }
        return "bell.badge"
    }

    private var liveUpdateHelp: String {
        let state = workspace.selectedState
        if let reason = state.liveUpdatePausedReason { return reason }
        return state.liveUpdatesEnabled
            ? String(localized: "Live updates are enabled")
            : String(localized: "Live updates are disabled")
    }

    private func requestClose(_ item: WorkspaceController.Item) {
        if item.state.workspaceHasUnsavedOutput {
            pendingCloseID = item.id
        } else {
            workspace.close(item.id)
        }
    }
}
