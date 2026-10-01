#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BIN="$(mktemp -t grapecompare-workspace-tests)"
trap 'rm -f "$BIN"' EXIT
swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
  -module-name GrapeCompareWorkspaceTests -o "$BIN" \
  ../GrapeCompare/Core/*.swift \
  ../GrapeCompare/AppState.swift \
  ../GrapeCompare/FileOperationController.swift \
  ../GrapeCompare/CompareFilesIntent.swift \
  workspace-integration.swift
"$BIN"
