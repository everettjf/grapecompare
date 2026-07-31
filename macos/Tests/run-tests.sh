#!/bin/bash
# Compiles the UI-independent core (DiffEngine + FolderComparator) together with
# the test harness in main.swift using swiftc, then runs the tests.
set -e
cd "$(dirname "$0")"
BIN="$(mktemp -t grapecompare-core-tests)"
swiftc -O -o "$BIN" \
    ../GrapeCompare/Core/DiffEngine.swift \
    ../GrapeCompare/Core/FolderComparator.swift \
    main.swift
"$BIN"
