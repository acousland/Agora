#!/bin/bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_dir"
version=${1:-$(cat Assets/version)}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: scripts/publish-release.sh major.minor.patch" >&2; exit 1; }
[[ $version == "$(cat Assets/version)" ]] || { echo "Update Assets/version first" >&2; exit 1; }
repo=acousland/Agora
tag="v$version"
[[ -z $(git status --porcelain) ]] || { echo "Commit all changes before publishing" >&2; exit 1; }
git fetch --quiet origin
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || { echo "Push main before publishing" >&2; exit 1; }
! git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1 || { echo "$tag already exists" >&2; exit 1; }
identity=${AGORA_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
[[ $identity == "Developer ID Application:"* ]] || { echo "Publishing requires a Developer ID Application signing identity." >&2; exit 1; }
export AGORA_SIGNING_IDENTITY="$identity"
swift test
python3 scripts/smoke-mcp.py
scripts/build-app.sh
app=dist/Agora.app
python3 scripts/test-outlook.py "$app"
profile=${AGORA_NOTARY_PROFILE:-renoir-notary}
notarized=0
if xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  ditto -c -k --keepParent "$app" dist/Agora-notarization.zip
  xcrun notarytool submit dist/Agora-notarization.zip --keychain-profile "$profile" --wait --output-format json > dist/notarization-result.json
  python3 -c 'import json; assert json.load(open("dist/notarization-result.json"))["status"] == "Accepted", "Notarisation was not accepted"'
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  notarized=1
elif [[ ${AGORA_ALLOW_UNNOTARIZED:-0} != 1 ]]; then
  echo "Notarisation profile '$profile' is unavailable. Set AGORA_NOTARY_PROFILE or explicitly use AGORA_ALLOW_UNNOTARIZED=1 for a signed, unnotarised release." >&2
  exit 1
fi
python3 scripts/smoke-mcp.py "$app/Contents/MacOS/AgoraMCP"
staging=$(mktemp -d "${TMPDIR:-/tmp}/agora-dmg.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Agora.app"
ln -s /Applications "$staging/Applications"
dmg="dist/Agora-$version.dmg"
hdiutil create -volname "Agora $version" -srcfolder "$staging" -ov -format UDZO "$dmg"
identity=${AGORA_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)}
[[ -n $identity ]] && codesign --force --timestamp --sign "$identity" "$dmg"
if [[ $notarized == 1 ]]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait --output-format json > dist/dmg-notarization-result.json
  python3 -c 'import json; assert json.load(open("dist/dmg-notarization-result.json"))["status"] == "Accepted"'
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature "$dmg"
fi
python3 scripts/sign-update.py "$dmg" > dist/update-signature.txt
python3 scripts/write-appcast.py "$version" "$dmg" dist/update-signature.txt
(cd dist && shasum -a 256 "Agora-$version.dmg" > "Agora-$version.dmg.sha256")
cp RELEASE_NOTES.md dist/release-notes.md
[[ $notarized == 1 ]] || printf '\nThis release is Developer ID signed but is not notarised.\n' >> dist/release-notes.md
git tag -a "$tag" -m "Agora $version"
git push origin "$tag"
gh release create "$tag" "$dmg" "$dmg.sha256" Sources/AgoraMac/Resources/Outlook/manifest.xml --repo "$repo" --title "Agora $version" --notes-file dist/release-notes.md
download="https://github.com/$repo/releases/download/$tag/Agora-$version.dmg"
curl --fail --location --retry 5 --retry-delay 3 "$download" -o dist/published-download.dmg
cmp "$dmg" dist/published-download.dmg
cp dist/appcast.xml appcast.xml
git add appcast.xml
git commit -m "Publish Sparkle feed for $version"
git push origin main
curl --fail --location --retry 5 "https://raw.githubusercontent.com/$repo/main/appcast.xml?release=$version" -o dist/published-appcast.xml
cmp appcast.xml dist/published-appcast.xml
echo "Published $tag. Notarised: $notarized. Sparkle signature and public download verified."
