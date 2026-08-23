#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BIN="$(mktemp -t grapecompare-core-benchmarks)"
CACHE_DIR="${TMPDIR:-/tmp}/grapecompare-swift-module-cache"
mkdir -p "$CACHE_DIR"
trap 'rm -f "$BIN"' EXIT

CLANG_MODULE_CACHE_PATH="$CACHE_DIR" \
SWIFT_MODULECACHE_PATH="$CACHE_DIR" \
swiftc -O -whole-module-optimization -o "$BIN" \
    ../GrapeCompare/Core/DiffEngine.swift \
    ../GrapeCompare/Core/FolderComparator.swift \
    ../GrapeCompare/Core/FileOperations.swift \
    ../GrapeCompare/Core/FolderSync.swift \
    ../GrapeCompare/Core/ImageComparison.swift \
    main.swift
"$BIN" "$@"
