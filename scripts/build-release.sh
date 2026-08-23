#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
raw_version="${1:-}"
version="${raw_version#v}"
output_dir="${2:-$project_root/dist}"
derived_data="${GRAPECOMPARE_DERIVED_DATA:-$(mktemp -d "${RUNNER_TEMP:-/tmp}/grapecompare-release.XXXXXX")}"

if [[ -z "$version" ]]; then
  echo "usage: $0 <version> [output-directory]" >&2
  exit 64
fi

mkdir -p "$output_dir" "$derived_data"
xcodebuild \
  -project "$project_root/macos/GrapeCompare.xcodeproj" \
  -scheme GrapeCompare \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_APP_SANDBOX=NO \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" \
  build

app_path="$derived_data/Build/Products/Release/GrapeCompare.app"
staging_dir="$output_dir/.staging"
staged_app="$staging_dir/GrapeCompare.app"
archive="$output_dir/GrapeCompare-$version.zip"
identity="${GRAPECOMPARE_SIGNING_IDENTITY:--}"
signing_options=(--force --deep --options runtime --sign "$identity")
if [[ "$identity" == "-" ]]; then signing_options+=(--timestamp=none); else signing_options+=(--timestamp); fi

codesign "${signing_options[@]}" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"
if codesign --display --entitlements :- "$app_path" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
  echo "direct-distribution build unexpectedly contains the App Sandbox entitlement" >&2
  exit 65
fi
mkdir -p "$staging_dir"
ditto "$app_path" "$staged_app"
lipo -verify_arch arm64 x86_64 "$staged_app/Contents/MacOS/GrapeCompare"
minimum_version="$(vtool -show-build "$staged_app/Contents/MacOS/GrapeCompare" | awk '/minos/{print $2; exit}')"
if [[ "$minimum_version" != "14.0" ]]; then
  echo "unexpected minimum macOS version: ${minimum_version:-unknown}" >&2
  exit 66
fi
ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$archive"
(cd "$output_dir" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Created $archive"
