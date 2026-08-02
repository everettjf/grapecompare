import SwiftUI

struct FileOperationHistorySheet: View {
    @Bindable var controller: FileOperationController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Operation History").font(.headline)
                    Text("Saved transactions remain protected by snapshot checks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            Divider()

            if controller.transactionHistory.isEmpty {
                ContentUnavailableView(
                    "No Operation History",
                    systemImage: "clock",
                    description: Text("Completed file operations will appear here."))
            } else {
                List(Array(controller.transactionHistory.reversed())) { transaction in
                    HistoryRow(
                        transaction: transaction,
                        isLatest: transaction.id == controller.lastTransaction?.id)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                if !controller.transactionHistory.isEmpty {
                    Button("Clear History…", role: .destructive) { confirmsClear = true }
                }
                Spacer()
                if controller.canUndo {
                    Button("Undo Latest") {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            controller.undoLastTransaction()
                        }
                    }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(.bar)
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 420, idealHeight: 520)
        .confirmationDialog(
            "Clear all operation history?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { controller.clearHistory() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes GrapeCompare’s private undo backups. Items already in the system Trash are not deleted.")
        }
    }
}

private struct HistoryRow: View {
    let transaction: FileOperationTransaction
    let isLatest: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLatest ? "arrow.uturn.backward.circle.fill" : "checkmark.circle")
                .foregroundStyle(isLatest ? .purple : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.completedAt, format: .dateTime.year().month().day().hour().minute())
                    if isLatest {
                        Text("Latest · Undoable")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                    }
                }
                Text(transaction.displayPaths.prefix(3).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(transaction.operationCount) operations")
                Text(ByteCountFormatter.string(fromByteCount: transaction.byteCount, countStyle: .file))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
