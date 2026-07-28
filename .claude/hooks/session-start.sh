#!/bin/bash
set -euo pipefail

# Only needed in Claude Code on the web — local dev machines have their own Godot install.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

GODOT_VERSION="4.7-stable"
GODOT_BIN="/usr/local/bin/godot"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ ! -x "$GODOT_BIN" ]; then
  echo "Installing headless Godot ${GODOT_VERSION}..."
  TMP_DIR="$(mktemp -d)"
  curl -fsSL \
    -o "$TMP_DIR/godot.zip" \
    "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
  unzip -q "$TMP_DIR/godot.zip" -d "$TMP_DIR"
  mv "$TMP_DIR/Godot_v${GODOT_VERSION}_linux.x86_64" "$GODOT_BIN"
  chmod +x "$GODOT_BIN"
  rm -rf "$TMP_DIR"
fi

# Warm the asset/script import cache (.godot/, gitignored) so later headless
# runs and scripts/godot_check.sh are fast instead of re-importing cold.
# Two passes: a fully-cold import can report a transient resource-ordering
# error (e.g. a .tres referencing a font before the font itself is imported)
# that resolves itself once the cache exists — the first pass just builds it,
# so only the second pass's log is worth keeping around.
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import > /dev/null 2>&1 || true
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import > /tmp/godot-import.log 2>&1 || true

echo "Godot ready: $("$GODOT_BIN" --version)"
