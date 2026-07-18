#!/usr/bin/env python3
"""Mirrors ground-lie gating — carry over water/sand must not count mid-flight."""


def ground_lie_applies(state: str) -> bool:
    """Water/OOB/sand/fairway/green only count on ROLL (loft is visual-only)."""
    return state == "ROLL"


def resolve_landing_lie(flight_groups: list[str], land_groups: list[str]) -> str | None:
    """Flight overlaps ignored; landing overlaps resolve. Sand beats fairway."""
    if not ground_lie_applies("ROLL"):
        return None
    if "water" in land_groups:
        return "Water"
    if "oob" in land_groups:
        return "OOB"
    if "sand" in land_groups:
        return "Sand"
    if "green" in land_groups:
        return "Green"
    if "fairway" in land_groups:
        return "Fairway"
    if "rough" in land_groups:
        return "Rough"
    return None


def classify_lie(pos: tuple[float, float], bunkers: list[tuple[tuple[float, float], float]], green_c, green_rx, green_ry, fairway_half: float) -> str:
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

    # Carry over water onto fairway
    assert resolve_landing_lie(["water"], ["fairway"]) == "Fairway"
    # Land in water
    assert resolve_landing_lie(["water"], ["water"]) == "Water"
    # Carry over bunker onto fairway
    assert resolve_landing_lie(["sand"], ["fairway"]) == "Fairway"
    # Land in bunker (also over fairway geometry)
    assert resolve_landing_lie(["sand"], ["fairway", "sand"]) == "Sand"

    bunkers = [((650.0, 380.0), 50.0)]
    assert classify_lie((650.0, 380.0), bunkers, (540.0, -80.0), 70.0, 60.0, 70.0) == "Sand"
    assert classify_lie((540.0, 400.0), bunkers, (540.0, -80.0), 70.0, 60.0, 70.0) == "Fairway"
    print("ground_lie_check: ok")


if __name__ == "__main__":
    main()
