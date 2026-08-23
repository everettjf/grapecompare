#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BIN="$(mktemp -t grapecompare-git-benchmarks)"
CACHE_DIR="${TMPDIR:-/tmp}/grapecompare-git-benchmark-module-cache"
mkdir -p "$CACHE_DIR"
trap 'rm -f "$BIN"' EXIT

CLANG_MODULE_CACHE_PATH="$CACHE_DIR" \
SWIFT_MODULECACHE_PATH="$CACHE_DIR" \
swiftc -O -whole-module-optimization -o "$BIN" \
    ../GrapeCompare/Core/GitRepository.swift \
    git-main.swift
"$BIN" "$@"
