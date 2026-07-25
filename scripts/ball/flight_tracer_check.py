#!/usr/bin/env python3
"""Contract: lofted flight tracer + up-and-in camera constants."""

from pathlib import Path

BALL = Path(__file__).with_name("ball.gd").read_text(encoding="utf-8")
HOLE = Path(__file__).resolve().parents[1].joinpath("course/hole_controller.gd").read_text(encoding="utf-8")


def flight_zoom(t: float, state: str = "FLIGHT") -> float:
    """Mirror HoleController._flight_camera_zoom."""
    launch, apex, land, start = 0.55, 0.58, 1.45, 0.55
    if state == "ROLL" or t >= 1.0:
        return land
    if t < start:
        return launch + (apex - launch) * (t / start)
    u = (t - start) / (1.0 - start)
    return apex + (land - apex) * u


def main() -> None:
    assert "const TRACER_LIFT := 0.35" in BALL
    assert "func air_progress()" in BALL
    assert "_spawn_ghost_arc" not in BALL
    assert "_ghost_arc" not in BALL
    assert "global_position + Vector2(0.0, -_height * TRACER_LIFT)" in BALL
    assert "func _mount_trail()" in BALL
    assert "_trail.z_index = 20" in BALL
    assert "_trail.width = 14.0" in BALL
    assert "TRAIL_TEX" not in BALL
    assert "call_deferred(\"_mount_trail\")" in BALL

    assert "const FLIGHT_ZOOM_LAUNCH := 0.55" in HOLE
    assert "const FLIGHT_ZOOM_LAND := 1.45" in HOLE
    assert "const FLIGHT_ZOOM_IN_START := 0.55" in HOLE
    assert "func _flight_camera_zoom()" in HOLE
    # Pure strike must not yank zoom back to aim framing mid-flight.
    pure = HOLE.split("func _on_pure_strike")[1].split("func ")[0]
    assert 'tween_property(camera, "zoom"' not in pure

    assert abs(flight_zoom(0.0) - 0.55) < 1e-6
    assert abs(flight_zoom(0.55) - 0.58) < 1e-6
    assert abs(flight_zoom(1.0) - 1.45) < 1e-6
    assert abs(flight_zoom(0.5, "ROLL") - 1.45) < 1e-6
    # Descent is the tight beat — mid-descent closer than apex.
    assert flight_zoom(0.85) > flight_zoom(0.4)
    print("flight_tracer_check: ok")


if __name__ == "__main__":
    main()
