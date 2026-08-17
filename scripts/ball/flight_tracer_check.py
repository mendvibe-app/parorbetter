#!/usr/bin/env python3
"""Contract: lofted flight tracer + up-and-in camera constants."""

from pathlib import Path

BALL = Path(__file__).with_name("ball.gd").read_text(encoding="utf-8")
HOLE = Path(__file__).resolve().parents[1].joinpath("course/hole_controller.gd").read_text(encoding="utf-8")


def flight_zoom(t: float, state: str = "FLIGHT", base: float = 1.2) -> float:
    """Mirror HoleController._flight_camera_zoom (relative to pre-shot aim base)."""
    launch = base * 1.0  # hold aim — never open past base
    apex = base * 1.05
    land = base * 1.28
    start = 0.55
    if state == "ROLL" or t >= 1.0:
        return land
    if t < start:
        return launch + (apex - launch) * (t / start)
    u = (t - start) / (1.0 - start)
    return apex + (land - apex) * u


def main() -> None:
    assert "const TRACER_LIFT := 0.35" in BALL
    assert "const TRACER_SCREEN_W" in BALL
    assert "func _sync_trail_visual" in BALL
    assert "func _sync_trail_gradient" in BALL
    assert "_trail_dry" in BALL
    assert "func air_progress()" in BALL
    assert "_spawn_ghost_arc" not in BALL
    assert "_ghost_arc" not in BALL
    assert "_height * lift" in BALL or "TRACER_LIFT /" in BALL
    assert "func _mount_trail()" in BALL
    assert "_trail.z_index = 20" in BALL
    assert "_trail.gradient" in BALL or "_trail_grad" in BALL
    assert "TRAIL_TEX" not in BALL
    assert "call_deferred(\"_mount_trail\")" in BALL
    # Space-based sampling for variable airspeed envelope (not 1-point-per-frame only).
    assert "TRACER_DESIRED_POINTS" in BALL
    assert "TRACER_MIN_SPACING" in BALL
    assert "distance_to" in BALL  # min spacing between trail points
    assert "get_point_position" in BALL  # Godot 4 Line2D API (not get_point)
    # Caps high enough that normal hang should not mid-chop the arc.
    assert "TRACER_CAP := 280" in BALL or "TRACER_CAP := 256" in BALL or "const TRACER_CAP" in BALL
    # No flight tracer on putts — the ball never leaves the ground, nothing to trace.
    # Structure: outer `if not _is_putt:` then FLIGHT (draw) / ROLL (wet-marker dry).
    assert "if not _is_putt:" in BALL
    assert "if state == State.FLIGHT:" in BALL
    assert "elif state == State.ROLL:" in BALL
    assert "TRACER_DRY_RATE" in BALL
    assert "elif state == State.ROLL and _is_putt:" not in BALL
    # Soft white land target: faint in flight; flash only on bounce, fades on roll.
    assert "func _show_land_mark" in BALL
    assert "func _planned_land_pos" in BALL
    assert "LAND_R_SCREEN" in BALL
    assert "_show_land_mark(_planned_land_pos(), false)" in BALL
    assert "_show_land_mark(global_position, true)" in BALL
    assert "_land_pulse = 1.0 if flash else 0.0" in BALL
    assert "_land_pulse - delta" in BALL
    # Tracer clears at _start_shot_ui, the single entry point every post-shot path
    # (aim, club-select, tap-in putt) runs through — not just at launch, and not only
    # on the aim-phase branch some paths (tap-in putts) skip entirely.
    assert "func clear_trail() -> void:" in BALL
    start_shot_ui = HOLE.split("func _start_shot_ui()")[1].split("\nfunc ")[0]
    assert "ball.clear_trail()" in start_shot_ui
    # Tracer color reflects execution using the SAME good/ok/bad palette already
    # used by the swing-trail color and tempo needle — not a new invented scheme.
    assert "Color(0.35, 0.92, 0.45, 0.92)" in BALL  # green — matches tempo_gesture.trail_color()
    assert "Color(0.95, 0.85, 0.25, 0.92)" in BALL  # amber
    assert "Color(0.95, 0.35, 0.3, 0.92)" in BALL  # red
    assert "ShotResult.ContactQuality.PERFECT:" in BALL
    # Spin curve is relative to launch dir — world-X only broke past-pin / side chips.
    assert "Vector2(spin * 28.0, 0.0)" not in BALL
    assert "flight_right * spin" in BALL or "roll_right * spin" in BALL
    assert "Vector2(-_launch_dir.y, _launch_dir.x)" in BALL

    assert "const FLIGHT_LAUNCH_FRAC := 1.0" in HOLE
    assert "const FLIGHT_APEX_FRAC := 1.05" in HOLE
    assert "const FLIGHT_LAND_FRAC := 1.28" in HOLE
    assert "const FLIGHT_ZOOM_IN_START := 0.55" in HOLE
    assert "func _flight_camera_zoom()" in HOLE
    assert "_flight_zoom_base" in HOLE
    # Follow seeds from aim zoom, not corridor floor (pin-primary must not pull out).
    follow = HOLE.split("func _follow_ball")[1].split("func ")[0]
    assert "_desired_camera_zoom()" in follow
    assert "_corridor_zoom_level() * 0.9" not in follow
    # Pure strike must not yank zoom back to aim framing mid-flight.
    pure = HOLE.split("func _on_pure_strike")[1].split("func ")[0]
    assert 'tween_property(camera, "zoom"' not in pure

    base = 1.2
    assert abs(flight_zoom(0.0, base=base) - base * 1.0) < 1e-6
    assert abs(flight_zoom(0.55, base=base) - base * 1.05) < 1e-6
    assert abs(flight_zoom(1.0, base=base) - base * 1.28) < 1e-6
    assert abs(flight_zoom(0.5, "ROLL", base=base) - base * 1.28) < 1e-6
    # Monotonic closer: launch holds base, never opens past aim, land tightest.
    assert flight_zoom(0.0, base=base) >= base - 1e-9
    assert flight_zoom(1.0, base=base) > flight_zoom(0.0, base=base)
    assert flight_zoom(0.85, base=base) > flight_zoom(0.4, base=base)
    print("flight_tracer_check: ok")


if __name__ == "__main__":
    main()
