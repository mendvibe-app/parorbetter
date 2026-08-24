#!/usr/bin/env python3
"""Densify green_* sprites to 768 — same mow motif, finer stripes. Filter stays Off."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "assets" / "greens"
OUT_DIR = Path(__file__).resolve().parent
SIZE = 768
PERIOD = 3

LIGHT = (108, 137, 70, 255)
MID = (92, 117, 62, 255)
DARK = (74, 95, 50, 255)
FRINGE = (70, 91, 46, 255)
EDGE = (83, 106, 56, 255)
FRINGE_PX = 18

DEFAULT_STEMS = (
	"green_oval",
	"green_kidney",
	"green_tiered",
	"green_long",
	"green_island",
)


def edge_distance(opaque: list[list[bool]]) -> list[list[int]]:
	inf = SIZE * 2
	dist = [[inf] * SIZE for _ in range(SIZE)]
	for y in range(SIZE):
		for x in range(SIZE):
			if not opaque[y][x]:
				dist[y][x] = 0
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


def densify(stem: str) -> Path:
	src_path = ASSETS / f"{stem}.png"
	src = Image.open(src_path).convert("RGBA")
	# Backup 128 only once
	bak = OUT_DIR / f"{stem}_128_backup.png"
	if src.size[0] <= 128 and not bak.exists():
		src.save(bak)

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

	out_path = OUT_DIR / f"{stem}_768.png"
	out.save(out_path)
	# Promote
	out.save(src_path)
	imp = ASSETS / f"{stem}.png.import"
	if imp.exists():
		imp.unlink()
	opaque_n = sum(1 for y in range(SIZE) for x in range(SIZE) if px[x, y][3] > 200)
	print(f"{stem}: 768 opaque={opaque_n} -> {src_path}")
	return out_path


def main() -> None:
	stems = sys.argv[1:] or list(DEFAULT_STEMS)
	for stem in stems:
		densify(stem)


if __name__ == "__main__":
	main()
