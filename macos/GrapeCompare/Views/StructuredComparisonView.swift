import SwiftUI

struct StructuredComparisonView: View {
    let differences: [StructuredDifference]
    @State private var query = ""

    private var filteredDifferences: [StructuredDifference] {
        StructuredDifference.filtered(differences, query: query)
    }

    var body: some View {
        let filtered = filteredDifferences
        VStack(spacing: 0) {
            HStack {
                TextField("Filter paths or values", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                if !query.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Clear Filter")
                }
                Spacer()
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(differences.count) structured differences")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(filtered.count) of \(differences.count) differences")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            Divider()
            if differences.isEmpty {
                ContentUnavailableView(
                    "Structured Values Are Equivalent",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Object key order and serialization format are ignored."))
            } else if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 16)
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No Matching Differences")
                        .font(.headline)
                    Text("Try another path or value, or clear the filter to see all differences.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("Clear Filter") { query = "" }
                    Spacer(minLength: 16)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filtered) {
                    TableColumn("Path") { difference in
                        Text(difference.path)
                            .font(Theme.mono)
                            .help(difference.path)
                            .textSelection(.enabled)
                    }
                    TableColumn("Change") { difference in
                        Text(difference.kind.localizedTitle)
                            .foregroundStyle(difference.kind.color)
                    }
                    TableColumn("Left") { difference in
                        Text(difference.left?.summary ?? "—")
                            .lineLimit(3)
                            .help(difference.left?.summary ?? "—")
                            .textSelection(.enabled)
                    }
                    TableColumn("Right") { difference in
                        Text(difference.right?.summary ?? "—")
                            .lineLimit(3)
                            .help(difference.right?.summary ?? "—")
                            .textSelection(.enabled)
                    }
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
    }
}

private extension StructuredDifferenceKind {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .added: "Added"
        case .removed: "Removed"
        case .changed: "Changed"
        case .typeChanged: "Type Changed"
        }
    }

    var color: Color {
        switch self {
        case .added: .green
        case .removed: .red
        case .changed: .orange
        case .typeChanged: .purple
        }
    }
}
