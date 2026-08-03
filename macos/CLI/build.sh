#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

OUTPUT="${1:-./.build/grapecompare}"
CACHE_DIR="${TMPDIR:-/tmp}/grapecompare-cli-module-cache"
mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$OUTPUT")"

CLANG_MODULE_CACHE_PATH="$CACHE_DIR" \
SWIFT_MODULECACHE_PATH="$CACHE_DIR" \
swiftc -O -whole-module-optimization -o "$OUTPUT" \
    ../GrapeCompare/Core/DiffEngine.swift \
    ../GrapeCompare/Core/TextComparison.swift \
    ../GrapeCompare/Core/UnifiedDiff.swift \
    ../GrapeCompare/Core/ThreeWayMerge.swift \
    ../GrapeCompare/Core/StructuredComparison.swift \
    ../GrapeCompare/Core/ImageComparison.swift \
    ../GrapeCompare/Core/GitRepository.swift \
    main.swift
