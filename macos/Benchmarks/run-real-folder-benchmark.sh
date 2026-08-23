#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <left-directory> <right-directory>" >&2
  exit 64
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/../.." && pwd)"
build_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/grapecompare-real-folder.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

swiftc -O \
  -module-cache-path "$build_dir/module-cache" \
  "$project_root"/macos/GrapeCompare/Core/*.swift \
  "$script_dir/RealFolderBenchmark.swift" \
  -o "$build_dir/real-folder-benchmark"

/usr/bin/time -lp "$build_dir/real-folder-benchmark" "$1" "$2"
