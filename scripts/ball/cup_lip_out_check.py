#!/usr/bin/env python3
"""Contract: cup lip-out presentation + ft-grounded leave (make rate frozen)."""
from __future__ import annotations

import re
from pathlib import Path

BALL = Path(__file__).with_name("ball.gd").read_text(encoding="utf-8")
HOLE = Path(__file__).resolve().parents[1].joinpath("course/hole_controller.gd").read_text(
	encoding="utf-8"
)


def main() -> int:
	# Capture geometry / see=catch frozen.
	assert "CUP_CAPTURE_RADIUS := 0.133" in BALL or "CUP_CAPTURE_RADIUS:=0.133" in BALL
	assert "CUP_CAPTURE_MAX_SPEED := 11.2" in BALL or "CUP_CAPTURE_MAX_SPEED:=11.2" in BALL
	assert "LIP_ORBIT_MAX := 0.175" in BALL or "LIP_ORBIT_MAX:=0.175" in BALL
	assert "LIP_OUT_REARM_PAD := 0.04" in BALL or "LIP_OUT_REARM_PAD:=0.04" in BALL

	# Helpers + separate stash (must not reuse make stash).
	assert "func _begin_lip_out" in BALL
	assert "func _finish_lip_out" in BALL
	assert "func _cancel_lip_out" in BALL
	assert "func _lip_out_exit_speed" in BALL
	assert "var _lip_out_offset" in BALL
	assert "var _lip_out_armed" in BALL
	assert "var _lip_out_playing" in BALL
	assert "var _lip_out_leave" in BALL
	assert "LIP_OUT_ORBIT" in BALL
	# Old 0.9×entry rocket leave removed.
	assert "LIP_OUT_SPEED_KEEP" not in BALL
	assert "LIP_OUT_EXIT_SIT" in BALL
	assert "LIP_OUT_EXIT_MAX" in BALL
	assert "LIP_OUT_EXIT_CHIP_MAX" in BALL
	assert "LIP_OUT_CHIP_LEAVE_MAX_YD" in BALL
	assert "ROLL_SPEED_FLOOR" in BALL

	m_sit = re.search(r"const LIP_OUT_EXIT_SIT\s*:=\s*([0-9.]+)", BALL)
	m_max = re.search(r"const LIP_OUT_EXIT_MAX\s*:=\s*([0-9.]+)", BALL)
	m_chip = re.search(r"const LIP_OUT_EXIT_CHIP_MAX\s*:=\s*([0-9.]+)", BALL)
	m_floor = re.search(r"const ROLL_SPEED_FLOOR\s*:=\s*([0-9.]+)", BALL)
	assert m_sit and m_max and m_chip and m_floor
	# Scaled with PUTT_PACE_SCALE (was 3 / 14).
	assert 0.7 <= float(m_sit.group(1)) <= 1.5, m_sit.group(1)
	assert 3.5 <= float(m_max.group(1)) <= 7.0, m_max.group(1)
	assert float(m_chip.group(1)) <= float(m_sit.group(1)) + 0.2, m_chip.group(1)
	assert float(m_floor.group(1)) <= 4.0, m_floor.group(1)
	assert "20.0" not in BALL.split("func _begin_roll")[1].split("func ")[0]

	begin = BALL.split("func _begin_lip_out")[1].split("func ")[0]
	finish = BALL.split("func _finish_lip_out")[1].split("func ")[0]
	exit_fn = BALL.split("func _lip_out_exit_speed")[1].split("func ")[0]
	capture = BALL.split("func _try_cup_capture")[1].split("func ")[0]

	# Lip-out never makes / never sinks.
	assert "settled.emit" not in begin
	assert "settled.emit" not in finish
	assert "play_cup_drop" not in begin
	assert "play_cup_drop" not in finish
	assert "_cup_entry_valid = true" not in begin
	assert "_cup_entry_valid = true" not in finish

	# Geometry-weighted luck (not bare 0.9×entry).
	assert "kick_tend" in exit_fn
	assert "randf()" in exit_fn
	assert "LIP_OUT_EXIT_CHIP_MAX" in exit_fn
	assert "not _is_putt" in exit_fn
	assert "_lip_out_exit_speed()" in finish
	assert "_lip_out_leave = true" in finish
	assert "_lip_out_leave_from" in finish
	PHYS = Path(__file__).resolve().parents[0].joinpath("ball_physics.gd").read_text(encoding="utf-8")
	assert "putt_decel_px()" in PHYS
	assert 'putt_decel_px() if lie == "Green"' in PHYS or "putt_decel_px() if lie == 'Green'" in PHYS
	roll = BALL.split("func _process_roll")[1].split("func ")[0]
	assert "LIP_OUT_CHIP_LEAVE_MAX_YD" in roll
	assert '_lie == "Green"' in roll or "_lie == 'Green'" in roll

	# Hot gate + firm-band chance inside make gate (hard putts can lip out on line).
	assert "CUP_CAPTURE_MAX_SPEED" in capture
	assert "_begin_lip_out" in capture
	assert "LIP_OUT_CHANCE_SPEED_MIN" in BALL
	assert "LIP_OUT_CHANCE_AT_MAX" in BALL
	assert "LIP_OUT_CHANCE_SPEED_MIN" in capture
	m_cmin = re.search(r"const LIP_OUT_CHANCE_SPEED_MIN\s*:=\s*([0-9.]+)", BALL)
	m_cmax = re.search(r"const LIP_OUT_CHANCE_AT_MAX\s*:=\s*([0-9.]+)", BALL)
	assert m_cmin and m_cmax
	assert 0.40 <= float(m_cmin.group(1)) <= 0.70, m_cmin.group(1)
	assert 0.25 <= float(m_cmax.group(1)) <= 0.55, m_cmax.group(1)

	# Resume ROLL after horseshoe (not SETTLED).
	assert "State.ROLL" in finish
	assert "State.SETTLED" not in finish

	# Leave uses putt settle; skips plan clamp.
	roll = BALL.split("func _process_roll")[1].split("func ")[0]
	assert "_lip_out_leave" in roll
	assert "not _lip_out_leave" in roll

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
	m_max_a = re.search(r"const LIP_OUT_ARC_MAX\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	assert m_min and m_max_a, "LIP_OUT_ARC_* missing"
	assert float(m_min.group(1)) >= 0.50, m_min.group(1)
	assert float(m_max_a.group(1)) >= 0.75, m_max_a.group(1)

	m_in_min = re.search(r"const LIP_IN_ARC_MIN\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	m_in_max = re.search(r"const LIP_IN_ARC_MAX\s*:=\s*TAU\s*\*\s*([0-9.]+)", BALL)
	assert m_in_min and m_in_max, "LIP_IN_ARC_* missing"
	# Short lip-in floor (not half-turn) — pours are straight; bowls only when earned.
	assert float(m_in_min.group(1)) <= 0.25, m_in_min.group(1)
	assert float(m_in_max.group(1)) >= 0.70, m_in_max.group(1)
	m_off = re.search(r"const LIP_CENTER_OFFSET_MAX\s*:=\s*([0-9.]+)", BALL)
	assert m_off
	# True-scale pour band (~0.36 of CUP_CAPTURE_RADIUS 0.133); was 0.68 pre-scale.
	assert 0.03 <= float(m_off.group(1)) <= 0.08, m_off.group(1)
	assert "func _cup_drop_params" in BALL
	# Pour decision is offset-led (speed must not AND-block center makes).
	params_fn = BALL.split("func _cup_drop_params")[1].split("func ")[0]
	assert "offset_ratio < LIP_CENTER_OFFSET_MAX" in params_fn
	assert "speed_ratio < LIP_CENTER_SPEED_MAX" not in params_fn

	print("cup_lip_out_check: ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
