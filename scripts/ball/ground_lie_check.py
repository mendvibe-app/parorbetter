#!/usr/bin/env python3
"""Mirrors ground-lie gating — surface under the ball while rolling."""

from pathlib import Path

# From GolfBall._process_roll — rough must drag harder than fairway.
FRICTION = {"Green": 1.8, "Fairway": 2.4, "Rough": 4.5, "Sand": 7.0, "Tee": 2.4}
HOLE = Path(__file__).resolve().parents[1].joinpath("course/hole_controller.gd").read_text(encoding="utf-8")
GREENS = Path(__file__).resolve().parents[2] / "assets" / "greens"


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
    sand_paint: dict[tuple[float, float], bool] | None = None,
) -> str:
    """sand_paint: optional (pos) -> on_sand. Without paint, circle (legacy / no-img fallback)."""
    for c, r in bunkers:
        if (pos[0] - c[0]) ** 2 + (pos[1] - c[1]) ** 2 > (r * 1.15) ** 2:
            continue
        if sand_paint is not None:
            if sand_paint.get(pos, False):
                return "Sand"
        else:
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

    # Paint-gated sand: inside design circle but transparent fringe ≠ Sand.
    center = (650.0, 380.0)
    fringe = (690.0, 380.0)  # inside r=50, not on painted sand
    paint = {center: True, fringe: False}
    assert classify_lie(center, bunkers, green, 70.0, 60.0, 70.0, paint) == "Sand"
    assert classify_lie(fringe, bunkers, green, 70.0, 60.0, 70.0, paint) == "Rough"

    # Early-hole large peninsula green must not share volume with island water.
    for rx, ry in [(58.0, 58.0), (48.0, 48.0), (36.0, 36.0)]:
        detect_r = (rx + 14.0 + ry + 14.0) * 0.5
        for rect in island_water_rects(rx, ry):
            assert not rect_intersects_circle(rect, 540.0, -80.0, detect_r + 10.0)

    # Painted silhouette gates Green (island beach / L cutouts ≠ putter).
    assert "_on_painted_green" in HOLE and "get_pixel" in HOLE
    # Sand lie matches painted bunker (same pattern as green).
    assert "_on_painted_sand" in HOLE
    assert "SAND_COLLISION_FRAC" in HOLE
    from PIL import Image

    kidney = Image.open(GREENS / "green_kidney.png").convert("RGBA")
    # Former mid-green bite must stay opaque — rough-through-hole forced wedges.
    assert kidney.getpixel((90, 50))[3] > 200, "kidney putting surface must be opaque"
    assert kidney.getpixel((64, 64))[3] > 200, "kidney center must be opaque"
    # Oval center must stay opaque (putting surface).
    oval = Image.open(GREENS / "green_oval.png").convert("RGBA")
    assert oval.getpixel((64, 64))[3] > 200

    # Bunker textures: center-ish sand, transparent corners (circle alone would over-fire).
    hazards = Path(__file__).resolve().parents[2] / "assets" / "hazards"
    for name in ("bunker_blob.png", "bunker_crescent.png", "bunker_cluster.png"):
        bimg = Image.open(hazards / name).convert("RGBA")
        w, h = bimg.size
        assert bimg.getpixel((w // 2, h // 2))[3] > 128 or any(
            bimg.getpixel((x, y))[3] > 128 for x in range(w) for y in range(h)
        ), f"{name} needs sand pixels"
        # Corner of texture is transparent fringe (outside painted sand).
        assert bimg.getpixel((2, 2))[3] < 40, f"{name} corner should be clear"

    print("ground_lie_check: ok")


if __name__ == "__main__":
    main()
