#!/bin/bash
set -euo pipefail

# Headless parse/import check: catches GDScript syntax errors, unresolved
# class_name references, and missing resource preloads that grep + the
# tempo_check.py / putt_stroke_check.py contract mirrors can't see.
# Does NOT catch gesture/visual/feel issues — those still need a real device.

GODOT_BIN="${GODOT_BIN:-/usr/local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -x "$GODOT_BIN" ]; then
  echo "godot_check: SKIPPED — no Godot binary at $GODOT_BIN (run .claude/hooks/session-start.sh, or set GODOT_BIN)" >&2
  exit 2
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# Two passes: see session-start.sh — a cold cache can report a transient
# resource-ordering error on the first pass that resolves on the second.
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import > "$LOG" 2>&1 || true
: > "$LOG"
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import > "$LOG" 2>&1 || true

if grep -qE "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$LOG"; then
  echo "godot_check: FAILED" >&2
  grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$LOG" >&2
  exit 1
fi

echo "godot_check: ok"
