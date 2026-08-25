#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/../.." && pwd)"
icon_dir="$project_root/macos/GrapeCompare/Assets.xcassets/AppIcon.appiconset"
expected=(
  "icon_16x16.png:16" "icon_16x16@2x.png:32"
  "icon_32x32.png:32" "icon_32x32@2x.png:64"
  "icon_128x128.png:128" "icon_128x128@2x.png:256"
  "icon_256x256.png:256" "icon_256x256@2x.png:512"
  "icon_512x512.png:512" "icon_512x512@2x.png:1024"
)

for item in "${expected[@]}"; do
  name="${item%%:*}"
  size="${item##*:}"
  metadata="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$icon_dir/$name")"
  grep -q "pixelWidth: $size" <<<"$metadata"
  grep -q "pixelHeight: $size" <<<"$metadata"
  grep -q "hasAlpha: yes" <<<"$metadata"
done

readme_metadata="$(sips -g pixelWidth -g pixelHeight -g hasAlpha \
  "$project_root/macos/GrapeCompare/Assets.xcassets/GrapeIcon.imageset/grape-icon.png")"
grep -q "pixelWidth: 1024" <<<"$readme_metadata"
grep -q "pixelHeight: 1024" <<<"$readme_metadata"
grep -q "hasAlpha: yes" <<<"$readme_metadata"

website_metadata="$(sips -g pixelWidth -g pixelHeight -g hasAlpha \
  "$project_root/docs/assets/app-icon.png")"
grep -q "pixelWidth: 1024" <<<"$website_metadata"
grep -q "pixelHeight: 1024" <<<"$website_metadata"
grep -q "hasAlpha: yes" <<<"$website_metadata"

echo "PASS: app, README, and website icon assets preserve transparent rounded corners"
