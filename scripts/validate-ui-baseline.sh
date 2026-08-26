#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

required_files=(
  docs/ui-quality-baseline.md
  docs/assets/file-diff.png
  docs/assets/folder-diff.png
)

for file in "${required_files[@]}"; do
  test -s "$file" || { echo "missing UI baseline: $file" >&2; exit 1; }
done

for image in docs/assets/file-diff.png docs/assets/folder-diff.png; do
  dimensions="$(sips -g pixelWidth -g pixelHeight "$image" 2>/dev/null)"
  grep -q 'pixelWidth: 2560' <<<"$dimensions"
  grep -q 'pixelHeight: 1600' <<<"$dimensions"
done

grep -q '720 × 560' docs/ui-quality-baseline.md
grep -q '1120 × 740' docs/ui-quality-baseline.md
grep -q 'Differentiate Without Color' docs/ui-quality-baseline.md
grep -q 'Reduce Motion' docs/ui-quality-baseline.md

echo "Validated UI quality baseline matrix and reference screenshots."
