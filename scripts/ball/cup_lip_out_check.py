#!/usr/bin/env python3
"""Contract: Phase 2 cup lip-out is presentation on hot rejects only (make rate frozen)."""
from __future__ import annotations

import re
from pathlib import Path

BALL = Path(__file__).with_name("ball.gd").read_text(encoding="utf-8")
HOLE = Path(__file__).resolve().parents[1].joinpath("course/hole_controller.gd").read_text(
	encoding="utf-8"
)


def main() -> int:
	# Capture geometry / see=catch frozen.
	assert "CUP_CAPTURE_RADIUS := 1.9" in BALL or "CUP_CAPTURE_RADIUS:=1.9" in BALL
	assert "CUP_CAPTURE_MAX_SPEED := 32.0" in BALL or "CUP_CAPTURE_MAX_SPEED:=32.0" in BALL

	# Helpers + separate stash (must not reuse make stash).
	assert "func _begin_lip_out" in BALL
	assert "func _finish_lip_out" in BALL
	assert "func _cancel_lip_out" in BALL
	assert "var _lip_out_offset" in BALL
	assert "var _lip_out_armed" in BALL
	assert "var _lip_out_playing" in BALL
	assert "LIP_OUT_SPEED_KEEP" in BALL
	assert "LIP_OUT_ORBIT" in BALL

	begin = BALL.split("func _begin_lip_out")[1].split("func ")[0]
	finish = BALL.split("func _finish_lip_out")[1].split("func ")[0]
	cancel = BALL.split("func _cancel_lip_out")[1].split("func ")[0]
	capture = BALL.split("func _try_cup_capture")[1].split("func ")[0]

	# Lip-out never makes / never sinks.
	assert "settled.emit" not in begin
	assert "settled.emit" not in finish
	assert "play_cup_drop" not in begin
	assert "play_cup_drop" not in finish
	assert "_cup_entry_valid = true" not in begin
	assert "_cup_entry_valid = true" not in finish

	# Hot gate still inside capture; lip-out called from that branch.
	assert "CUP_CAPTURE_MAX_SPEED" in capture
	assert "_begin_lip_out" in capture

	# Resume ROLL after horseshoe (not SETTLED).
	assert "State.ROLL" in finish
	assert "State.SETTLED" not in finish

	# Controllers unchanged — no lip-out wiring in hole_controller.
	assert "_begin_lip_out" not in HOLE
	assert "_lip_out_" not in HOLE

	# reset_at / launch clear lip-out.
	reset = BALL.split("func reset_at")[1].split("func ")[0]
	launch = BALL.split("func launch")[1].split("func ")[0]
	assert "_cancel_lip_out" in reset
	assert "_cancel_lip_out" in launch or "_clear_lip_out" in launch

	# Orbit held at Phase 1 rim shelf (grey overhang OK — arc angle carries legibility).
	m = re.search(r"const LIP_OUT_ORBIT\s*:=\s*LIP_ORBIT_MAX", BALL)
	assert m, "LIP_OUT_ORBIT should reuse LIP_ORBIT_MAX"

	# Arc length band: half→¾+ turn (not quarter-curl nudges).
	m_min = re.search(r"const LIP_OUT_ARC_MIN\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	m_max = re.search(r"const LIP_OUT_ARC_MAX\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	assert m_min and m_max, "LIP_OUT_ARC_* missing"
	assert float(m_min.group(1)) >= 0.50, m_min.group(1)
	assert float(m_max.group(1)) >= 0.75, m_max.group(1)

	m_in_min = re.search(r"const LIP_IN_ARC_MIN\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	m_in_max = re.search(r"const LIP_IN_ARC_MAX\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	assert m_in_min and m_in_max, "LIP_IN_ARC_* missing"
	assert float(m_in_min.group(1)) >= 0.45, m_in_min.group(1)
	assert float(m_in_max.group(1)) >= 0.70, m_in_max.group(1)

	print("cup_lip_out_check: ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
