#!/usr/bin/env bash
# Usage: ./scripts/release.sh 0.3.0
# Tags a release on GitHub, then points the Homebrew formula in ../homebrew-tap at it.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: ./scripts/release.sh 0.3.0}"
TAG="v$VERSION"
TAP_DIR="${TAP_DIR:-../homebrew-tap}"
FORMULA="$TAP_DIR/Formula/pitstop.rb"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first."; exit 1; }
[[ -f "$FORMULA" ]] || { echo "Formula not found at $FORMULA. Clone your tap there or set TAP_DIR."; exit 1; }

# owner/pitstop from either git@github.com:owner/pitstop.git or https://github.com/owner/pitstop.git
REPO=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')

# Version shown in Finder and About.
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" Resources/Info.plist
git commit -am "Release $TAG" || true
git tag "$TAG"
git push origin HEAD "$TAG"

URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
TMP=$(mktemp)
echo "Downloading $URL"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsSL -o "$TMP" "$URL" && break
  sleep 3
done
SHA=$(shasum -a 256 "$TMP" | awk '{print $1}')
rm -f "$TMP"

sed -i '' -E \
  -e "s#^  homepage \".*\"#  homepage \"https://github.com/$REPO\"#" \
  -e "s#^  url \".*\"#  url \"$URL\"#" \
  -e "s#^  sha256 \".*\"#  sha256 \"$SHA\"#" \
  "$FORMULA"

(cd "$TAP_DIR" && git commit -am "pitstop $VERSION" && git push)

echo
echo "Released $TAG."
echo "Teammates update with: brew update && brew upgrade pitstop && pitstop app install"
