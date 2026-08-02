import SwiftUI

struct FileOperationReviewSheet: View {
    @Bindable var controller: FileOperationController

    init(controller: FileOperationController) {
        self.controller = controller
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 650, idealWidth: 720, minHeight: 470, idealHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard.fill")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review File Operation Plan")
                    .font(.headline)
                Text("Nothing changes until you execute this reviewed plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .preparing:
            workingView(
                title: "Inspecting the real filesystem…",
                detail: "Counting hidden items, bytes, links, and current destinations.")
        case .ready:
            if let plan = controller.plan { planView(plan) }
        case .executing:
            progressView(title: "Executing plan…")
        case .undoing:
            progressView(title: "Undoing completed operations…")
        case .finished:
            resultView
        case .idle:
            if let error = controller.errorMessage {
                errorView(error)
            } else {
                workingView(title: "Preparing plan…", detail: "")
            }
        }
    }

    private func planView(_ plan: FileOperationPlan) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                summaryMetric("\(plan.operations.count)", label: "operations")
                summaryMetric("\(plan.itemCount)", label: "filesystem items")
                summaryMetric(ByteCountFormatter.string(fromByteCount: plan.byteCount, countStyle: .file), label: "to process")
                Spacer()
            }
            .padding(18)

            if plan.replacementCount > 0 || plan.trashCount > 0 || plan.moveCount > 0 {
                warningBanner(plan)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }

            Picker("If an item fails", selection: $controller.failurePolicy) {
                Text("Stop on First Failure").tag(FileOperationFailurePolicy.stopOnFirstFailure)
                Text("Continue After Failures").tag(FileOperationFailurePolicy.continueAfterFailures)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .accessibilityHint("Controls whether later reviewed items run after one item fails")

            List(plan.operations) { operation in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: operation.kind))
                        .foregroundStyle(color(for: operation.kind))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(operation.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(operationDescription(operation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(operation.itemCount) items")
                        Text(ByteCountFormatter.string(fromByteCount: operation.byteCount, countStyle: .file))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
    }

    private func warningBanner(_ plan: FileOperationPlan) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Review destructive changes carefully")
                    .font(.subheadline.weight(.semibold))
                Text(warningText(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.25))
        }
    }

    private func progressView(title: LocalizedStringKey) -> some View {
        VStack(spacing: 18) {
            Image(systemName: controller.phase == .undoing ? "arrow.uturn.backward.circle" : "arrow.left.arrow.right.circle")
                .font(.system(size: 46))
                .foregroundStyle(.purple)
            Text(title).font(.title3)
            if let progress = controller.progress {
                ProgressView(value: fraction(progress))
                    .frame(maxWidth: 420)
                Text("\(progress.completedOperations) of \(progress.totalOperations) operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rate = progress.bytesPerSecond {
                    HStack(spacing: 10) {
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file))/s")
                        if let remaining = progress.estimatedTimeRemaining {
                            Text("About \(Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))) remaining")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let remaining = progress.estimatedTimeRemaining {
                    Text("About \(Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !progress.currentPath.isEmpty {
                    Text(progress.currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)
                }
            } else {
                ProgressView().controlSize(.large)
            }
            if controller.phase == .executing {
                Text("Cancel stops before the next safe commit. Completed operations remain undoable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultView: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: resultIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(resultColor)
                Text(resultTitle).font(.title3)

                if controller.wasCancelled {
                    Text("Pending operations were cancelled. Any completed operations are listed in the transaction and can be undone.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let error = controller.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                if !controller.failures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Items that could not be completed")
                            .font(.headline)
                        ForEach(controller.failures) { failure in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.relativePath).font(.system(.body, design: .monospaced))
                                Text(failure.message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                if controller.canUndo {
                    Label(
                        controller.persistenceWarning == nil
                            ? "Undo is saved and remains available after relaunch while outputs stay unchanged."
                            : "Undo is available while this app session remains open.",
                        systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let warning = controller.persistenceWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Plan is no longer safe to execute").font(.title3)
            Text(error)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Inspect Again") { controller.preparePlan() }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func workingView(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(title).font(.title3)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if controller.phase == .ready {
                Button("Inspect Again") { controller.preparePlan() }
            }
            Spacer()
            switch controller.phase {
            case .ready:
                Button("Cancel") { controller.closeReview() }
                    .keyboardShortcut(.cancelAction)
                Button("Execute Plan", role: .destructive) { controller.executePlan() }
                    .keyboardShortcut(.defaultAction)
            case .executing:
                Button("Cancel Pending Work", role: .destructive) { controller.cancelCurrentWork() }
            case .finished:
                if controller.canUndo {
                    Button("Undo Last Operation") { controller.undoLastTransaction() }
                        .keyboardShortcut("z", modifiers: [.command])
                }
                Button("Done") { controller.closeReview() }
                    .keyboardShortcut(.defaultAction)
            case .idle:
                Button("Close") { controller.closeReview() }
                    .keyboardShortcut(.cancelAction)
            case .preparing:
                Button("Cancel") { controller.closeReview() }
                    .keyboardShortcut(.cancelAction)
            case .undoing:
                EmptyView()
            }
        }
        .padding(14)
        .background(.bar)
    }

    private func summaryMetric(_ value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fraction(_ progress: FileOperationProgress) -> Double {
        if progress.totalBytes > 0 {
            return min(1, Double(progress.completedBytes) / Double(progress.totalBytes))
        }
        guard progress.totalOperations > 0 else { return 0 }
        return min(1, Double(progress.completedOperations) / Double(progress.totalOperations))
    }

    private func operationDescription(_ operation: PreparedFileOperation) -> String {
        switch (operation.kind, operation.draft.sourceSide) {
        case (.copy, .left): return String(localized: "Copy · Left → Right")
        case (.copy, .right): return String(localized: "Copy · Right → Left")
        case (.replace, .left): return String(localized: "Replace with backup · Left → Right")
        case (.replace, .right): return String(localized: "Replace with backup · Right → Left")
        case (.move, .left): return String(localized: "Move · Left → Right")
        case (.move, .right): return String(localized: "Move · Right → Left")
        case (.trash, .left): return String(localized: "Move left item to Trash")
        case (.trash, .right): return String(localized: "Move right item to Trash")
        }
    }

    private func warningText(_ plan: FileOperationPlan) -> String {
        var parts: [String] = []
        if plan.replacementCount > 0 {
            parts.append(String(localized: "Destinations to replace: \(plan.replacementCount)"))
        }
        if plan.moveCount > 0 {
            parts.append(String(localized: "Sources to move: \(plan.moveCount)"))
        }
        if plan.trashCount > 0 {
            parts.append(String(localized: "Items to move to Trash: \(plan.trashCount)"))
        }
        return parts.joined(separator: "; ") + ". " +
            String(localized: "Preconditions are checked again immediately before each commit.")
    }

    private func icon(for kind: FileOperationKind) -> String {
        switch kind {
        case .copy: "doc.on.doc"
        case .replace: "arrow.triangle.2.circlepath"
        case .move: "folder.badge.arrow.forward"
        case .trash: "trash"
        }
    }

    private func color(for kind: FileOperationKind) -> Color {
        switch kind {
        case .copy: .blue
        case .replace: .orange
        case .move: .purple
        case .trash: .red
        }
    }

    private var resultIcon: String {
        if controller.errorMessage != nil || !controller.failures.isEmpty { return "exclamationmark.triangle.fill" }
        if controller.wasCancelled { return "stop.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var resultColor: Color {
        if controller.errorMessage != nil || !controller.failures.isEmpty { return .orange }
        if controller.wasCancelled { return .secondary }
        return .green
    }

    private var resultTitle: LocalizedStringKey {
        if controller.errorMessage != nil { return "Undo could not be completed" }
        if !controller.failures.isEmpty { return "Plan completed with some failures" }
        if controller.wasCancelled { return "Pending work cancelled" }
        if controller.lastTransaction == nil { return "Undo complete" }
        return "Plan complete"
    }
}
