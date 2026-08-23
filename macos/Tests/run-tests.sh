#!/bin/bash
# Compiles the UI-independent core (DiffEngine + FolderComparator) together with
# the test harness in main.swift using swiftc, then runs the tests.
set -euo pipefail
cd "$(dirname "$0")"
BIN="$(mktemp -t grapecompare-core-tests)"
CACHE_DIR="${TMPDIR:-/tmp}/grapecompare-swift-test-module-cache"
mkdir -p "$CACHE_DIR"
trap 'rm -f "$BIN"' EXIT

CLANG_MODULE_CACHE_PATH="$CACHE_DIR" \
SWIFT_MODULECACHE_PATH="$CACHE_DIR" \
swiftc -O -whole-module-optimization -o "$BIN" \
    ../GrapeCompare/Core/DiffEngine.swift \
    ../GrapeCompare/Core/TextComparison.swift \
    ../GrapeCompare/Core/UnifiedDiff.swift \
    ../GrapeCompare/Core/ThreeWayMerge.swift \
    ../GrapeCompare/Core/ExternalMergeProtocol.swift \
    ../GrapeCompare/Core/StructuredComparison.swift \
    ../GrapeCompare/Core/ImageComparison.swift \
    ../GrapeCompare/Core/GitRepository.swift \
    ../GrapeCompare/Core/FolderComparator.swift \
    ../GrapeCompare/Core/FileOperations.swift \
    ../GrapeCompare/Core/FileOperationPersistence.swift \
    ../GrapeCompare/Core/ComparisonSessionStore.swift \
    ../GrapeCompare/Core/FilesystemWatcher.swift \
    main.swift
"$BIN"
