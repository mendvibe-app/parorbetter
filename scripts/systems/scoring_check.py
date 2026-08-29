#!/usr/bin/env python3
"""Contract: ace is strokes==1 copy, Result enum stays eagle/albatross."""
from pathlib import Path

SRC = Path(__file__).with_name("scoring.gd").read_text(encoding="utf-8")

assert "enum Result { ALBATROSS, EAGLE, BIRDIE, PAR, BOGEY, DOUBLE_PLUS }" in SRC
assert "Result.ACE" not in SRC
assert "func is_ace" in SRC
assert "func hole_label" in SRC
assert '"Hole in One"' in SRC
print("scoring_check: OK")
