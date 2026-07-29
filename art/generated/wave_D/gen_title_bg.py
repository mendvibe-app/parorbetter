#!/usr/bin/env python3
"""Kit title plate — hard-pixel course from live STYLE assets (no soft dusk plate)."""

from pathlib import Path
from PIL import Image, ImageDraw
import random

ROOT = Path(__file__).resolve().parents[3]  # repo root
OUT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"

# Portrait mobile plate (2× nearest → 1080×1920)
W, H = 540, 960

# STYLE anchors
SKY_TOP = (42, 58, 72, 255)
SKY_MID = (90, 110, 100, 255)
SKY_GLOW = (200, 170, 110, 255)
ROUGH = (48, 65, 46, 255)
ROUGH_D = (36, 50, 34, 255)
ROUGH_HI = (73, 87, 62, 255)
GREEN = (90, 120, 70, 255)
GREEN_D = (70, 95, 55, 255)
SAND = (186, 152, 107, 255)


def main() -> None:
	rng = random.Random(7)
	img = Image.new("RGBA", (W, H), SKY_TOP)
	px = img.load()

	# --- Sky bands (hard steps, no soft AA) ---
	horizon = int(H * 0.38)
	for y in range(horizon):
		t = y / max(horizon - 1, 1)
		if t < 0.55:
			u = t / 0.55
			c = _lerp(SKY_TOP, SKY_MID, u)
		else:
			u = (t - 0.55) / 0.45
			c = _lerp(SKY_MID, SKY_GLOW, u * 0.85)
		# chunky cloud flecks
		for x in range(W):
			if rng.random() < 0.012 and t < 0.7:
				px[x, y] = _lerp(c, (30, 36, 40, 255), 0.35)
			else:
				px[x, y] = c

	# --- Ground: rough fill ---
	for y in range(horizon, H):
		for x in range(W):
			t = (y - horizon) / max(H - horizon, 1)
			base = ROUGH if (x // 3 + y // 2) % 2 == 0 else ROUGH_D
			if rng.random() < 0.08:
				base = ROUGH_HI
			# darken toward bottom
			if t > 0.7:
				base = _lerp(base, (22, 28, 20, 255), (t - 0.7) / 0.3 * 0.5)
			px[x, y] = base

	# --- Fairway corridor (perspective-ish taper) ---
	fairway = Image.open(ASSETS / "terrain" / "fairway_tile_a.png").convert("RGBA")
	fw = fairway.resize((64, 64), Image.NEAREST)
	fw_px = fw.load()
	cx = W // 2
	for y in range(horizon - 8, H):
		t = (y - (horizon - 8)) / max(H - horizon + 8, 1)
		# half-width grows toward camera
		half = int(28 + t * 140)
		# slight curve
		ox = int(6 * __import__("math").sin(t * 2.2))
		for x in range(cx - half + ox, cx + half + ox):
			if not (0 <= x < W):
				continue
			# edge soft hard-step rough blend
			edge = min(x - (cx - half + ox), (cx + half + ox) - 1 - x)
			if edge < 0:
				continue
			u = (x - (cx - half + ox)) % 64
			v = (y * 2) % 64
			c = fw_px[u, v]
			if edge < 3:
				c = _lerp(c, ROUGH, 0.55)
			elif edge < 6:
				c = _lerp(c, ROUGH_HI, 0.25)
			px[x, y] = c

	# --- Green oval near mid-fairway ---
	gx, gy = cx + 8, horizon + 70
	grx, gry = 52, 28
	for y in range(gy - gry, gy + gry + 1):
		for x in range(gx - grx, gx + grx + 1):
			if not (0 <= x < W and 0 <= y < H):
				continue
			nx = (x - gx) / grx
			ny = (y - gy) / gry
			if nx * nx + ny * ny <= 1.0:
				px[x, y] = GREEN if (x + y) % 3 else GREEN_D
	# thin sand ring (bunker crescent)
	for y in range(gy - gry - 4, gy + 8):
		for x in range(gx - grx - 10, gx - grx + 8):
			if 0 <= x < W and 0 <= y < H:
				nx = (x - (gx - grx - 2)) / 12
				ny = (y - gy) / 18
				if nx * nx + ny * ny < 1.0 and rng.random() < 0.85:
					px[x, y] = SAND

	# --- Canopy trees (live kit sprites) ---
	trees = []
	for name in ("tree_round.png", "tree_dark.png", "tree_cluster.png", "tree_broad.png"):
		p = ASSETS / "background" / name
		if p.is_file():
			trees.append(Image.open(p).convert("RGBA"))
	if trees:
		# left tree line
		for i, (tx, ty, sc) in enumerate(
			[
				(40, horizon + 20, 1.4),
				(70, horizon + 90, 1.1),
				(30, horizon + 180, 1.6),
				(55, horizon + 280, 1.2),
				(25, horizon + 400, 1.8),
				(W - 50, horizon + 40, 1.3),
				(W - 80, horizon + 120, 1.0),
				(W - 40, horizon + 220, 1.5),
				(W - 70, horizon + 340, 1.2),
				(W - 35, horizon + 460, 1.7),
			]
		):
			tr = trees[i % len(trees)]
			tw = int(tr.width * sc * 0.55)
			th = int(tr.height * sc * 0.55)
			tr2 = tr.resize((max(tw, 8), max(th, 8)), Image.NEAREST)
			img.alpha_composite(tr2, (tx - tr2.width // 2, ty - tr2.height // 2))

	# --- Pin on green ---
	pin = ASSETS / "greens" / "pin_flag.png"
	if pin.is_file():
		pf = Image.open(pin).convert("RGBA")
		pf = pf.resize((28, 40), Image.NEAREST)
		img.alpha_composite(pf, (gx - 6, gy - 38))

	# hard pixel outline vignette (chunky, not soft blur)
	for y in range(H):
		for x in range(W):
			edge = min(x, y, W - 1 - x, H - 1 - y)
			if edge < 6:
				a = 0.55 if edge < 2 else 0.25
				px[x, y] = _lerp(px[x, y], (12, 16, 12, 255), a)

	OUT.mkdir(parents=True, exist_ok=True)
	path = OUT / "title_kit.png"
	img.save(path)
	# 2× for review + full-res ship
	img2 = img.resize((W * 2, H * 2), Image.NEAREST)
	img2.save(OUT / "title_kit_x2.png")
	# Live path size ~1080×1920
	img2.save(ROOT / "assets" / "background" / "title_dusk.png")
	print("wrote", path, "and assets/background/title_dusk.png", img2.size)


def _lerp(a, b, t: float):
	t = max(0.0, min(1.0, t))
	return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


if __name__ == "__main__":
	main()
