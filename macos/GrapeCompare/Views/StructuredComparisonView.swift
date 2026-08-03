import SwiftUI

struct StructuredComparisonView: View {
    let differences: [StructuredDifference]
    @State private var query = ""

    private var filteredDifferences: [StructuredDifference] {
        guard !query.isEmpty else { return differences }
        return differences.filter {
            $0.path.localizedCaseInsensitiveContains(query) ||
                $0.left?.summary.localizedCaseInsensitiveContains(query) == true ||
                $0.right?.summary.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter paths or values", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Text("\(differences.count) structured differences")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            if differences.isEmpty {
                ContentUnavailableView(
                    "Structured Values Are Equivalent",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Object key order and serialization format are ignored."))
            } else {
                Table(filteredDifferences) {
                    TableColumn("Path") { difference in
                        Text(difference.path)
                            .font(Theme.mono)
                            .textSelection(.enabled)
                    }
                    TableColumn("Change") { difference in
                        Text(difference.kind.localizedTitle)
                            .foregroundStyle(difference.kind.color)
                    }
                    TableColumn("Left") { difference in
                        Text(difference.left?.summary ?? "—")
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                    TableColumn("Right") { difference in
                        Text(difference.right?.summary ?? "—")
                            .lineLimit(3)
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
