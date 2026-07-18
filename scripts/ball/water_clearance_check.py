#!/usr/bin/env python3
"""Mirrors GolfBall ground-hazard gating — fails if carry-over-water is treated as wet."""


def ground_hazard_applies(state: str) -> bool:
    """Water/OOB only count when the ball is not in FLIGHT (airborne carry)."""
    return state != "FLIGHT"


def landing_in_hazard(flight_overlapped: bool, land_overlapped: bool, land_state: str) -> bool:
    """Flight overlap is ignored; hazard resolves from landing overlap + ground state."""
    if not land_overlapped:
        return False
    return ground_hazard_applies(land_state)


def main() -> None:
    assert not ground_hazard_applies("FLIGHT")
    assert ground_hazard_applies("ROLL")
    assert ground_hazard_applies("SETTLED")
    # Carry over water onto land
    assert not landing_in_hazard(True, False, "ROLL")
    # Land in water
    assert landing_in_hazard(True, True, "ROLL")
    # Still airborne over water — not wet yet
    assert not landing_in_hazard(True, True, "FLIGHT")
    print("water_clearance_check: ok")


if __name__ == "__main__":
    main()
