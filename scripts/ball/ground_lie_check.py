#!/usr/bin/env python3
"""Mirrors ground-lie gating — surface under the ball while rolling."""

# From GolfBall._process_roll — rough must drag harder than fairway.
FRICTION = {"Green": 1.8, "Fairway": 2.4, "Rough": 4.5, "Sand": 7.0, "Tee": 2.4}


def ground_lie_applies(state: str) -> bool:
    """Water/OOB/surfaces only count on ROLL (loft is visual-only)."""
    return state == "ROLL"


def resolve_landing_lie(flight_groups: list[str], land_groups: list[str]) -> str | None:
    """Flight overlaps ignored; landing overlaps resolve. Green beats water; sand beats fairway."""
    if not ground_lie_applies("ROLL"):
        return None
    if "oob" in land_groups:
        return "OOB"
    if "green" in land_groups:
        return "Green"
    if "water" in land_groups:
        return "Water"
    if "sand" in land_groups:
        return "Sand"
    if "fairway" in land_groups:
        return "Fairway"
    if "rough" in land_groups:
        return "Rough"
    return None


def island_water_rects(green_rx: float, green_ry: float, green_y: float = -80.0) -> list[tuple[float, float, float, float]]:
    """Mirror HoleController ISLAND water — must clear green + ball sensor."""
    clear = max(green_rx, green_ry) + 14.0 + 12.0
    side_w, side_h = 90.0, 160.0
    side_y = green_y - 30.0
    return [
        (540.0 - clear - side_w, side_y, side_w, side_h),
        (540.0 + clear, side_y, side_w, side_h),
        (540.0 - 100.0, green_y + clear, 200.0, 70.0),
    ]


def rect_intersects_circle(rect: tuple[float, float, float, float], cx: float, cy: float, r: float) -> bool:
    x, y, w, h = rect
    nx = min(max(cx, x), x + w)
    ny = min(max(cy, y), y + h)
    return (cx - nx) ** 2 + (cy - ny) ** 2 < r * r


def classify_lie(
    pos: tuple[float, float],
    bunkers: list[tuple[tuple[float, float], float]],
    green_c,
    green_rx,
    green_ry,
    fairway_half: float,
) -> str:
    for c, r in bunkers:
        if (pos[0] - c[0]) ** 2 + (pos[1] - c[1]) ** 2 <= r * r:
            return "Sand"
    dx = (pos[0] - green_c[0]) / max(green_rx, 1.0)
    dy = (pos[1] - green_c[1]) / max(green_ry, 1.0)
    if dx * dx + dy * dy <= 1.0:
        return "Green"
    fx = abs(pos[0] - 540.0)
    if fx <= fairway_half + 20.0:
        return "Fairway"
    return "Rough"


def main() -> None:
    assert not ground_lie_applies("FLIGHT")
    assert ground_lie_applies("ROLL")
    assert not ground_lie_applies("IDLE")

    assert resolve_landing_lie(["water"], ["fairway"]) == "Fairway"
    assert resolve_landing_lie(["water"], ["water"]) == "Water"
    assert resolve_landing_lie(["water"], ["water", "green"]) == "Green"
    assert resolve_landing_lie(["sand"], ["fairway"]) == "Fairway"
    assert resolve_landing_lie(["sand"], ["fairway", "sand"]) == "Sand"

    bunkers = [((650.0, 380.0), 50.0)]
    green = (540.0, -80.0)
    assert classify_lie((650.0, 380.0), bunkers, green, 70.0, 60.0, 70.0) == "Sand"
    assert classify_lie((540.0, 400.0), bunkers, green, 70.0, 60.0, 70.0) == "Fairway"
    # Off fairway → rough, and rough must slow the roll more than fairway
    assert classify_lie((700.0, 400.0), bunkers, green, 70.0, 60.0, 70.0) == "Rough"
    assert FRICTION["Rough"] > FRICTION["Fairway"]
    assert FRICTION["Sand"] > FRICTION["Rough"]

    # Early-hole large peninsula green must not share volume with island water.
    for rx, ry in [(58.0, 58.0), (48.0, 48.0), (36.0, 36.0)]:
        detect_r = (rx + 14.0 + ry + 14.0) * 0.5
        for rect in island_water_rects(rx, ry):
            assert not rect_intersects_circle(rect, 540.0, -80.0, detect_r + 10.0)
    print("ground_lie_check: ok")


if __name__ == "__main__":
    main()
