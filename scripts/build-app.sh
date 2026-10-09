#!/bin/bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_dir"
version=${AGORA_VERSION:-$(cat Assets/version)}
build_number=${AGORA_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
[[ $build_number -gt 0 ]] || build_number=1
configuration=${AGORA_CONFIGURATION:-release}
swift build -c "$configuration"
bin_dir=$(swift build -c "$configuration" --show-bin-path)
app_dir="$project_dir/dist/Agora.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$app_dir/Contents/Frameworks"
cp "$bin_dir/Agora" "$bin_dir/AgoraMCP" "$app_dir/Contents/MacOS/"
resource_bundle=$(find "$bin_dir" -maxdepth 1 -name 'Agora_AgoraMac.bundle' -print -quit)
[[ -n $resource_bundle ]] || { echo "Missing Outlook resource bundle" >&2; exit 1; }
ditto "$resource_bundle" "$app_dir/Contents/Resources/Agora_AgoraMac.bundle"
cp scripts/setup-outlook.sh "$app_dir/Contents/Resources/"
[[ ! -f Assets/Agora.icns ]] || cp Assets/Agora.icns "$app_dir/Contents/Resources/"
sparkle_framework=$(find .build/artifacts/sparkle -path '*/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit)
[[ -n $sparkle_framework ]] || { echo "Missing Sparkle framework" >&2; exit 1; }
ditto "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
python3 scripts/write-plist.py "$app_dir/Contents/Info.plist" "$version" "$build_number"
identity=${AGORA_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
if [[ -z $identity ]]; then
  codesign --force --deep --sign - "$app_dir"
else
  sign=(codesign --force --options runtime --timestamp --sign "$identity")
  sparkle="$app_dir/Contents/Frameworks/Sparkle.framework"
  "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
  "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
  "${sign[@]}" "$sparkle/Versions/B/Autoupdate"
  "${sign[@]}" "$sparkle/Versions/B/Updater.app"
  "${sign[@]}" "$sparkle"
  "${sign[@]}" "$app_dir/Contents/MacOS/AgoraMCP"
  "${sign[@]}" "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
