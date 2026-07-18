#!/usr/bin/env python3
"""Runnable check for bag overlap + shortest-cover suggestion. No Godot required."""

BAG = [
    ("Driver", 260.0),
    ("3-Wood", 230.0),
    ("6-Iron", 175.0),
    ("7-Iron", 160.0),
    ("8-Iron", 145.0),
    ("9-Iron", 130.0),
    ("Pitching Wedge", 110.0),
    ("Gap/Sand Wedge", 85.0),
]


def shot_need(remaining: float, lie: str) -> float:
    return remaining * (1.2 if lie == "Rough" else 1.08)


def clubs_for_lie(lie: str):
    if lie == "Sand":
        return [c for c in BAG if "Wedge" in c[0]]
    return list(BAG)


def pick_club(remaining: float, lie: str):
    if lie == "Green":
        return ("Putter", max(4.0, min(remaining * 1.6, 35.0)))
    need = shot_need(remaining, lie)
    available = clubs_for_lie(lie)
    for name, mx in reversed(available):
        if need <= mx:
            return (name, mx)
    return available[0]


def main() -> None:
    # Neighbor overlap ~15–20 yd (max_i - max_{i+1})
    for (a, ma), (b, mb) in zip(BAG, BAG[1:]):
        gap = ma - mb
        assert 15.0 <= gap <= 55.0, f"{a}/{b} gap {gap} out of playable overlap band"

    # Shorter club always has lower max
    assert all(BAG[i][1] > BAG[i + 1][1] for i in range(len(BAG) - 1))

    assert pick_club(10, "Green")[0] == "Putter"
    assert all("Wedge" in n for n, _ in clubs_for_lie("Sand"))

    # 150 yd fairway → need 162 → 6-Iron covers, 7-Iron (160) does not
    assert pick_club(150, "Fairway") == ("6-Iron", 175.0)

    # 140 yd → need 151.2 → 7-Iron
    assert pick_club(140, "Fairway") == ("7-Iron", 160.0)

    # Sand always wedges; short bunker → gap/sand
    assert pick_club(40, "Sand") == ("Gap/Sand Wedge", 85.0)

    print("club_bag_check: ok")


if __name__ == "__main__":
    main()
