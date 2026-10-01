import Foundation

@main
struct WorkspaceIntegrationTests {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ name: String) {
            print("\(value ? "PASS" : "FAIL"): \(name)")
            if !value { failures += 1 }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "GrapeCompareTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = AppState(storageDirectory: directory, preferences: preferences)
        state.liveUpdatesEnabled = false
        defer { state.prepareForClose() }
        func settle() async throws {
            for _ in 0..<1000 {
                if state.comparisonPhase == .idle && !state.isImportingClipboardImage { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw CocoaError(.coderReadCorrupt)
        }
        let left = directory.appendingPathComponent("left")
        let right = directory.appendingPathComponent("right")
        for folder in [left, right] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for name in ["a.txt", "b.txt", "same.txt"] {
            try Data((name == "same.txt" ? "same" : "before \(name)").utf8).write(to: left.appendingPathComponent(name))
            try Data((name == "same.txt" ? "same" : "after \(name)").utf8).write(to: right.appendingPathComponent(name))
        }
        state.leftFolderURL = left; state.rightFolderURL = right
        state.startFolderCompare()
        try await settle()
        check(state.folderRoot != nil, "folder review loads a real directory tree")
        state.folderReviewFiles = FolderReviewPolicy.files(in: state.folderRoot!)
        check(state.folderReviewFiles.map(\.name) == ["a.txt", "b.txt"], "review sequence excludes identical files")
        state.openDiff(for: state.folderReviewFiles[0])
        try await settle()
        check(state.isFolderWorkspace && state.activeFolderFileID == "a.txt" && state.fileDiff != nil,
              "opening a folder file preserves folder review context")
        state.outputText = "edited output"; state.outputIsDirty = true
        state.navigateFolderFile(1)
        check(state.showsNavigationConfirmation && state.activeFolderFileID == "a.txt" && state.outputIsDirty,
              "cross-file navigation protects unsaved output")
        state.resolveFileNavigation(save: nil)
        check(state.activeFolderFileID == "a.txt" && state.outputText == "edited output",
              "cancel preserves the current file and edits")
        state.navigateFolderFile(1)
        state.resolveFileNavigation(save: true)
        try await settle()
        let savedOutput = try String(contentsOf: right.appendingPathComponent("a.txt"), encoding: .utf8)
        check(state.activeFolderFileID == "b.txt" && savedOutput == "edited output",
              "save-and-continue writes the original destination then navigates")
        check(state.incomingDifferenceDirection == 1, "forward navigation requests the first incoming difference")
        state.outputText = "discard this"; state.outputIsDirty = true
        state.navigateFolderFile(-1)
        state.resolveFileNavigation(save: false, discard: true)
        try await settle()
        check(state.activeFolderFileID == "a.txt" && !state.outputIsDirty && state.incomingDifferenceDirection == -1,
              "discard-and-continue opens the previous file and requests its last difference")
        state.outputText = "must survive"; state.outputIsDirty = true
        try Data("external change".utf8).write(to: right.appendingPathComponent("a.txt"))
        state.navigateFolderFile(1)
        state.resolveFileNavigation(save: true)
        check(state.activeFolderFileID == "a.txt" && state.outputIsDirty && state.outputError != nil,
              "save conflict blocks navigation and preserves edits")
        state.resolveFileNavigation(save: nil)
        state.prepareComparisonShelf()
        let third = directory.appendingPathComponent("third.txt")
        try Data("third".utf8).write(to: third)
        state.stageInputs([third], automaticallyCompare: false)
        check(state.shelfItems.count == 3 && state.outputText == "must survive", "adding a shelf version does not interrupt dirty output")
        state.shelfRight = third
        state.prepareComparisonShelf()
        check(state.shelfRight == third && state.outputText == "must survive",
              "reopening the shelf preserves pending A/B choices and dirty output")
        let removedInput = state.diffRightURL!
        state.removeShelfItem(removedInput)
        state.prepareComparisonShelf()
        check(!state.shelfItems.contains(removedInput) && state.shelfRight == third,
              "reopening the shelf does not restore a deliberately removed input")
        state.compareShelfPair()
        check(state.showsNavigationConfirmation && state.diffRightURL != third, "shelf switching uses the same unsaved-output guard")
        state.resolveFileNavigation(save: false, discard: true)
        try await settle()
        check(state.diffRightURL == third && !state.isFolderWorkspace, "shelf comparison opens selected versions after confirmation")
        state.shelfLeft = third
        state.shelfRight = state.diffLeftURL
        state.prepareComparisonShelf()
        check(state.shelfLeft == state.diffLeftURL && state.shelfRight == third,
              "a new comparison initializes the shelf to its active pair")
        state.goHome(); state.clearShelf()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        state.importClipboardImageData(png)
        try await settle()
        check(state.shelfItems.count == 1 && state.screen == .home, "first pasted image remains staged")
        state.importClipboardImageData(png)
        try await settle()
        check(state.shelfItems.count == 2 && state.screen == .fileDiff && state.imageComparison != nil,
              "two pasted images produce independent snapshots and start an image comparison")
        let snapshots = state.shelfItems
        state.importClipboardImageData(Data("not an image".utf8))
        try await settle()
        check(state.shelfItems == snapshots && state.quickCompareError != nil, "invalid clipboard data leaves the current comparison intact")
        for snapshot in snapshots { try? FileManager.default.removeItem(at: snapshot) }
        if failures > 0 { throw CocoaError(.validationMissingMandatoryProperty) }
        print("ALL WORKSPACE INTEGRATION TESTS PASSED")
    }
}
