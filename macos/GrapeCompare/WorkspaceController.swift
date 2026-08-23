import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceController {
    struct Item: Identifiable {
        let id: UUID
        let state: AppState
    }

    private(set) var items: [Item]
    var selectedID: Item.ID

    init() {
        let first = Item(id: UUID(), state: AppState())
        items = [first]
        selectedID = first.id
    }

    var selectedState: AppState {
        items.first(where: { $0.id == selectedID })?.state ?? items[0].state
    }

    @discardableResult
    func addComparison() -> Item.ID {
        let item = Item(id: UUID(), state: AppState(processLaunchArguments: false))
        items.append(item)
        selectedID = item.id
        return item.id
    }

    func select(_ id: Item.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func close(_ id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].state.canCloseWorkspaceItem else { return }
        let wasSelected = selectedID == id
        items[index].state.prepareForClose()
        items.remove(at: index)
        if items.isEmpty {
            let replacement = Item(id: UUID(), state: AppState(processLaunchArguments: false))
            items = [replacement]
            selectedID = replacement.id
        } else if wasSelected {
            selectedID = items[min(index, items.count - 1)].id
        }
    }
}
