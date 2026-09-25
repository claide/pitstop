#!/usr/bin/env bash
# Builds Pitstop.app (with the `pitstop` command inside) into dist/.
# --install: copies it to /Applications, links `pitstop` onto your PATH, and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

OUT="dist/Pitstop.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Helpers" "$OUT/Contents/Resources"
cp "$BIN_DIR/Pitstop" "$OUT/Contents/MacOS/Pitstop"
cp "$BIN_DIR/PitstopCLI" "$OUT/Contents/Helpers/pitstop"
cp Resources/Info.plist "$OUT/Contents/Info.plist"

# Swift's generated Bundle.module accessor looks for this bundle at the app's
# own root (sibling of Contents), so that's the only place it needs to ship.
# It must NOT also go in Contents/MacOS: codesign treats anything there as a
# nested code component and fails with "bundle format unrecognized" on a
# plain resource bundle. Its name is always <package>_<target>.
if [[ -d "$BIN_DIR/Pitstop_Pitstop.bundle" ]]; then
  cp -R "$BIN_DIR/Pitstop_Pitstop.bundle" "$OUT/Pitstop_Pitstop.bundle"
fi

# Ad-hoc signatures, fine for your own Macs. Sign the helper before the app.
codesign --force --sign - "$OUT/Contents/Helpers/pitstop"

# codesign warns "unsealed contents present in the bundle root" because the
# resource bundle sits outside Contents/ — expected and harmless here, but it
# can exit non-zero on some codesign versions, which would silently kill this
# script (set -e) before the --install step below ever runs. Only treat it as
# fatal if it's a different error.
if ! CODESIGN_LOG=$(codesign --force --sign - "$OUT" 2>&1); then
  if ! grep -q "unsealed contents present in the bundle root" <<< "$CODESIGN_LOG"; then
    echo "$CODESIGN_LOG" >&2
    exit 1
  fi
  echo "Note: $CODESIGN_LOG"
fi
echo "Built $OUT"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Pitstop 2>/dev/null || true
  rm -rf /Applications/Pitstop.app
  cp -R "$OUT" /Applications/

  if [[ -w /opt/homebrew/bin ]]; then
    LINK_DIR=/opt/homebrew/bin
  else
    LINK_DIR="$HOME/.local/bin"
    mkdir -p "$LINK_DIR"
  fi
  ln -sf /Applications/Pitstop.app/Contents/Helpers/pitstop "$LINK_DIR/pitstop"
  echo "Linked $LINK_DIR/pitstop"
  if ! command -v pitstop >/dev/null 2>&1; then
    echo "Add $LINK_DIR to your PATH so execute-jira can run \`pitstop\`."
  fi

  open /Applications/Pitstop.app
  echo "Installed to /Applications and launched."
fi