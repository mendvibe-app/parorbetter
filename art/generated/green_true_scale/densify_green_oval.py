#!/usr/bin/env python3
"""G1: densify green_oval to 768 — same mow motif, finer stripes. Filter stays Off."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "assets" / "greens" / "green_oval.png"
OUT_DIR = Path(__file__).resolve().parent
SIZE = 768
PERIOD = 3  # light/dark column width in source px (~inches on large greens)

LIGHT = (108, 137, 70, 255)
MID = (92, 117, 62, 255)
DARK = (74, 95, 50, 255)
FRINGE = (70, 91, 46, 255)
EDGE = (83, 106, 56, 255)
FRINGE_PX = 18


def edge_distance(opaque: list[list[bool]]) -> list[list[int]]:
    """Chessboard distance to transparent; INF if deep interior."""
    inf = SIZE * 2
    dist = [[inf] * SIZE for _ in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            if not opaque[y][x]:
                dist[y][x] = 0
    # Forward
    for y in range(SIZE):
        for x in range(SIZE):
            if dist[y][x] == 0:
                continue
            best = dist[y][x]
            if y:
                best = min(best, dist[y - 1][x] + 1)
            if x:
                best = min(best, dist[y][x - 1] + 1)
            if y and x:
                best = min(best, dist[y - 1][x - 1] + 1)
            if y and x + 1 < SIZE:
                best = min(best, dist[y - 1][x + 1] + 1)
            dist[y][x] = best
    # Backward
    for y in range(SIZE - 1, -1, -1):
        for x in range(SIZE - 1, -1, -1):
            best = dist[y][x]
            if y + 1 < SIZE:
                best = min(best, dist[y + 1][x] + 1)
            if x + 1 < SIZE:
                best = min(best, dist[y][x + 1] + 1)
            if y + 1 < SIZE and x + 1 < SIZE:
                best = min(best, dist[y + 1][x + 1] + 1)
            if y + 1 < SIZE and x:
                best = min(best, dist[y + 1][x - 1] + 1)
            dist[y][x] = best
    return dist


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    alpha_big = src.split()[-1].resize((SIZE, SIZE), Image.NEAREST)
    ga = alpha_big.load()
    opaque = [[ga[x, y] > 200 for x in range(SIZE)] for y in range(SIZE)]
    dist = edge_distance(opaque)

    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if not opaque[y][x]:
                continue
            band = (x // PERIOD) % 2
            jitter = ((x * 17 + y * 31) ^ (x * y)) & 7
            if band == 0:
                c = LIGHT if jitter < 3 else MID
            else:
                c = DARK if jitter < 4 else MID
            d = dist[y][x]
            if d <= FRINGE_PX:
                t = 1.0 - d / float(FRINGE_PX)
                if t > 0.35:
                    c = FRINGE if jitter < 4 else EDGE
                elif t > 0.15:
                    c = EDGE if jitter < 3 else MID
            px[x, y] = c

    out_path = OUT_DIR / "green_oval_768.png"
    out.save(out_path)
    cx = cy = SIZE // 2
    peep = out.crop((cx - 32, cy - 32, cx + 32, cy + 32)).resize((512, 512), Image.NEAREST)
    peep.save(OUT_DIR / "green_oval_768_center_8x.png")
    opaque_n = sum(1 for y in range(SIZE) for x in range(SIZE) if px[x, y][3] > 200)
    print(f"wrote {out_path} size={out.size} opaque={opaque_n}")


if __name__ == "__main__":
    main()
