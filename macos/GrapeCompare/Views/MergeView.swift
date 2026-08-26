import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MergeView: View {
    @Environment(AppState.self) private var state
    @State private var exportsResult = false
    @State private var resultDocument = TextPatchDocument(text: "")
    @State private var resultText = ""
    @State private var exportError: String?
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.isComparingMerge {
                ProgressView("Merging…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.mergeError {
                ContentUnavailableView(
                    "Merge Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if state.imageMergeBaseData != nil {
                imageConflictResolver
            } else if let result = state.mergeResult {
                HSplitView {
                    conflictList(result)
                        .frame(minWidth: 300, idealWidth: 380)
                    outputEditor(result)
                        .frame(minWidth: 480)
                }
            }
        }
        .modifier(TextPatchExportModifier(
            isPresented: $exportsResult,
            legacyDocument: resultDocument,
            text: resultText,
            contentType: .plainText,
            defaultFilename: "merged.txt") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            })
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Save Failed", isPresented: Binding(
            get: { state.mergeSaveError != nil },
            set: { if !$0 { state.mergeSaveError = nil } }
        )) {
            Button("OK") { state.mergeSaveError = nil }
        } message: {
            Text(state.mergeSaveError ?? "")
        }
        .confirmationDialog(
            "Discard merge output?",
            isPresented: $confirmsDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { leaveMerge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Export the merge result before leaving if you want to keep it.")
        }
    }

    private var header: some View {
        ComparisonTopBar(backAction: {
                if state.mergeOutputIsDirty { confirmsDiscard = true } else { leaveMerge() }
        }) {
            pathLabel("Base", url: state.baseFileURL, color: .secondary)
            pathLabel("Ours", url: state.oursFileURL, color: .blue)
            pathLabel("Theirs", url: state.theirsFileURL, color: .purple)
            Spacer()
            if state.imageMergeBaseData != nil {
                if let choice = state.imageMergeChoice {
                    Text("Selected: \(choice.rawValue.capitalized)")
                        .foregroundStyle(.green)
                } else {
                    Text("Choose the image to keep")
                        .foregroundStyle(.orange)
                }
                Button(state.isExternalMerge ? "Save Merge and Close" : "Export Result…") {
                    state.saveImageMerge()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.imageMergeChoice == nil)
            } else if let result = state.mergeResult {
                Button {
                    state.selectAdjacentMergeConflict(offset: -1)
                } label: {
                    Label("Previous Conflict", systemImage: "chevron.up")
                }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(result.conflicts.isEmpty)
                Button {
                    state.selectAdjacentMergeConflict(offset: 1)
                } label: {
                    Label("Next Conflict", systemImage: "chevron.down")
                }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(result.conflicts.isEmpty)
                Text("\(result.conflictCount) conflicts")
                    .foregroundStyle(result.conflictCount == 0 ? .green : .orange)
                Text("\(state.mergeChoices.count) of \(result.conflictCount) resolved")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(state.mergeChoices.count == result.conflictCount ? .green : .secondary)
                if state.isExternalMerge {
                    Button("Save Merge and Close") { state.saveExternalMerge() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.mergeChoices.count < result.conflictCount || state.mergeOutputHasConflictMarkers)
                } else {
                    Button("Export Result…") {
                        resultText = state.mergeOutputText
                        resultDocument = TextPatchDocument(text: resultText)
                        exportsResult = true
                    }
                    .disabled(state.mergeChoices.count < result.conflictCount || state.mergeOutputHasConflictMarkers)
                }
            }
        }
    }

    private var imageConflictResolver: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Image Conflict Resolution", systemImage: "photo.on.rectangle.angled")
                    .font(.title2.bold())
                Spacer()
                if let ours = state.imageMergeOursDifference,
                   let theirs = state.imageMergeTheirsDifference {
                    Text("Ours: \(ours.differingPixelCount) px · Theirs: \(theirs.differingPixelCount) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)

            HStack(spacing: 14) {
                imageChoiceCard("Base", choice: .base, data: state.imageMergeBaseData)
                imageChoiceCard("Ours", choice: .ours, data: state.imageMergeOursData)
                imageChoiceCard("Theirs", choice: .theirs, data: state.imageMergeTheirsData)
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
        .padding(.vertical, 16)
    }

    private func imageChoiceCard(
        _ title: LocalizedStringResource,
        choice: ImageMergeChoice,
        data: Data?
    ) -> some View {
        Button {
            state.chooseImageMerge(choice)
        } label: {
            VStack(spacing: 10) {
                Text(title).font(.headline)
                if let data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                } else {
                    ContentUnavailableView("Image Unavailable", systemImage: "photo.badge.exclamationmark")
                }
                Label(
                    state.imageMergeChoice == choice ? "Selected" : "Choose",
                    systemImage: state.imageMergeChoice == choice ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(state.imageMergeChoice == choice ? Color.green : Color.secondary)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(state.imageMergeChoice == choice ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: state.imageMergeChoice == choice ? 3 : 1)
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(state.imageMergeChoice == choice ? "Selected" : "Not selected")
    }

    private func pathLabel(_ title: LocalizedStringResource, url: URL?, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).bold()
            Text(url?.lastPathComponent ?? "—")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private func conflictList(_ result: ThreeWayMergeResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Conflicts")
                .font(.headline)
                .padding(10)
            Divider()
            if result.conflicts.isEmpty {
                ContentUnavailableView(
                    "No Conflicts",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Independent and identical changes were merged automatically."))
            } else {
                List(result.conflicts, selection: Binding(
                    get: { state.selectedMergeConflictID },
                    set: { state.selectedMergeConflictID = $0 }
                )) { conflict in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base lines \(rangeDescription(conflict.baseRange))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            choiceButton("Base", .base, conflict)
                            choiceButton("Ours", .ours, conflict)
                            choiceButton("Theirs", .theirs, conflict)
                            choiceButton("Both", .both, conflict)
                        }
                        Text(preview(conflict))
                            .font(Theme.monoSmall)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Conflict at base lines \(rangeDescription(conflict.baseRange))")
                    .accessibilityValue(state.mergeChoices[conflict.id]?.rawValue ?? "Unresolved")
                    .tag(conflict.id)
                }
            }
        }
    }

    private func outputEditor(_ result: ThreeWayMergeResult) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editable Merge Output").font(.headline)
                if state.mergeChoices.count < result.conflictCount {
                    Text("Resolve every conflict before export")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if state.mergeOutputHasConflictMarkers {
                    Label("Conflict markers remain in the output", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(10)
            Divider()
            TextEditor(text: Binding(
                get: { state.mergeOutputText },
                set: { state.updateMergeOutput($0) }
            ))
            .font(Theme.mono)
            .accessibilityLabel("Editable three-way merge output")
        }
    }

    private func choiceButton(
        _ title: LocalizedStringResource,
        _ choice: MergeConflictChoice,
        _ conflict: MergeConflict
    ) -> some View {
        Button(title) { state.resolveMergeConflict(conflict.id, with: choice) }
            .buttonStyle(.bordered)
            .tint(state.mergeChoices[conflict.id] == choice ? .accentColor : .secondary)
            .accessibilityValue(state.mergeChoices[conflict.id] == choice ? "Selected" : "Not selected")
    }

    private func preview(_ conflict: MergeConflict) -> String {
        let ours = conflict.oursLines.prefix(2).map(\.content).joined(separator: " ⏎ ")
        let theirs = conflict.theirsLines.prefix(2).map(\.content).joined(separator: " ⏎ ")
        return "Ours: \(ours)\nTheirs: \(theirs)"
    }

    private func rangeDescription(_ range: Range<Int>) -> String {
        if range.isEmpty { return "\(range.lowerBound + 1) (insertion)" }
        return "\(range.lowerBound + 1)–\(range.upperBound)"
    }

    private func leaveMerge() {
        if state.isExternalMerge { state.cancelExternalMerge() } else { state.goHome() }
    }
}
