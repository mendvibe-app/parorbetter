#!/usr/bin/env python3
"""Hard-pixel lie glance icons + lie-preview widgets — Pixel Kit Golf."""

from pathlib import Path
from PIL import Image
import random

OUT = Path(__file__).resolve().parent

# STYLE.md terrain anchors
FW_LIGHT = (100, 126, 61, 255)   # #647E3D
FW_MID = (84, 104, 53, 255)      # #546835
FW_DARK = (61, 82, 40, 255)      # #3D5228
RG_GROUND = (73, 87, 62, 255)    # #49573E
RG_DARK = (48, 65, 46, 255)      # #30412E
RG_HI = (122, 154, 74, 255)      # #7A9A4A
GN_MID = (90, 120, 70, 255)      # quieter green surface
GN_LIGHT = (110, 140, 85, 255)
GN_DARK = (70, 95, 55, 255)
SAND_L = (212, 187, 146, 255)    # #D4BB92
SAND_M = (186, 152, 107, 255)    # #BA986B
SAND_D = (139, 107, 69, 255)     # #8B6B45
TEE_BOX = (90, 120, 55, 255)
TEE_PEG = (230, 220, 190, 255)
TEE_PEG_D = (180, 160, 120, 255)
BALL = (245, 245, 240, 255)
BALL_SHADE = (200, 200, 195, 255)
OUTLINE = (26, 31, 26, 255)


def new_img(w, h):
	return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def set_px(img, x, y, c):
	if 0 <= x < img.width and 0 <= y < img.height:
		img.putpixel((x, y), c)


def fill_rect(img, x0, y0, x1, y1, c):
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			set_px(img, x, y, c)


def fill_ellipse(img, cx, cy, rx, ry, c):
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			nx = (x - cx) / max(rx, 0.001)
			ny = (y - cy) / max(ry, 0.001)
			if nx * nx + ny * ny <= 1.0:
				set_px(img, x, y, c)


def outline_nonzero(img, color=OUTLINE):
	w, h = img.size
	src = img.copy()
	for y in range(h):
		for x in range(w):
			if src.getpixel((x, y))[3] != 0:
				continue
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					if dx == 0 and dy == 0:
						continue
					nx, ny = x + dx, y + dy
					if 0 <= nx < w and 0 <= ny < h and src.getpixel((nx, ny))[3] > 0:
						set_px(img, x, y, color)
						break


def draw_ball(img, cx, cy, r=6):
	fill_ellipse(img, cx, cy, r, r, BALL)
	fill_ellipse(img, cx - 1, cy - 1, max(1, r // 3), max(1, r // 3), (255, 255, 255, 255))
	fill_ellipse(img, cx + 2, cy + 2, max(1, r // 3), max(1, r // 3), BALL_SHADE)


def fleck_disc(img, cx, cy, rx, ry, base, flecks, rng, density=0.12):
	fill_ellipse(img, cx, cy, rx, ry, base)
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			nx = (x - cx) / max(rx, 0.001)
			ny = (y - cy) / max(ry, 0.001)
			if nx * nx + ny * ny > 1.0:
				continue
			if rng.random() < density:
				set_px(img, x, y, rng.choice(flecks))


# --- 64×64 glance icons -------------------------------------------------

def lie_fairway():
	img = new_img(64, 64)
	rng = random.Random(1)
	fleck_disc(img, 32, 34, 24, 20, FW_MID, [FW_LIGHT, FW_DARK], rng, 0.14)
	# thin mow hint bands
	for y in range(20, 50, 3):
		for x in range(10, 54):
			nx = (x - 32) / 24
			ny = (y - 34) / 20
			if nx * nx + ny * ny <= 0.92 and (x + y) % 5 == 0:
				set_px(img, x, y, FW_LIGHT)
	draw_ball(img, 32, 32, 7)
	outline_nonzero(img)
	return img


def lie_green():
	img = new_img(64, 64)
	rng = random.Random(2)
	# quieter, smoother — fewer flecks
	fleck_disc(img, 32, 34, 24, 20, GN_MID, [GN_LIGHT, GN_DARK], rng, 0.05)
	draw_ball(img, 32, 32, 7)
	outline_nonzero(img)
	return img


def lie_rough():
	import math

	img = new_img(64, 64)
	rng = random.Random(3)
	# Solid body first so outline stays a clean disc; tips grow outward from rim.
	fleck_disc(img, 32, 34, 22, 18, RG_GROUND, [RG_DARK, RG_HI], rng, 0.30)
	for a in range(0, 360, 10):
		rad = math.radians(a)
		# Start on the rim so tips stay attached (no orphan pixels).
		x0 = int(32 + math.cos(rad) * 21)
		y0 = int(34 + math.sin(rad) * 17)
		h = rng.randint(2, 4)
		for i in range(h):
			x = int(x0 + math.cos(rad) * i)
			y = int(y0 + math.sin(rad) * i)
			set_px(img, x, y, RG_HI if i % 2 == 0 else RG_DARK)
	draw_ball(img, 32, 33, 6)
	outline_nonzero(img)
	return img


def lie_sand():
	img = new_img(64, 64)
	rng = random.Random(4)
	fleck_disc(img, 32, 34, 26, 18, SAND_M, [SAND_L, SAND_D], rng, 0.18)
	# rake lines
	for y in range(24, 48, 4):
		for x in range(12, 52):
			nx = (x - 32) / 26
			ny = (y - 34) / 18
			if nx * nx + ny * ny <= 0.85:
				set_px(img, x, y, SAND_L)
	draw_ball(img, 32, 32, 7)
	outline_nonzero(img)
	return img


def lie_tee():
	img = new_img(64, 64)
	# hard pixel tee peg + ball on top
	# stem
	fill_rect(img, 30, 28, 33, 52, TEE_PEG)
	fill_rect(img, 31, 28, 32, 52, TEE_PEG_D)
	# cup head
	fill_rect(img, 26, 24, 37, 28, TEE_PEG)
	fill_rect(img, 27, 23, 36, 24, TEE_PEG)
	fill_rect(img, 28, 22, 35, 23, TEE_PEG)
	# dimple in cup
	fill_rect(img, 29, 25, 34, 27, TEE_PEG_D)
	draw_ball(img, 32, 18, 7)
	outline_nonzero(img)
	return img


# --- 256×96 side-on widgets ---------------------------------------------

def _grass_strip(img, base, hi, dark, tip_amp, rng, density=0.2):
	"""Fill lower half with textured ground + irregular top silhouette."""
	w, h = img.size
	ground_y = int(h * 0.52)
	# base fill
	for y in range(ground_y, h):
		for x in range(w):
			t = (y - ground_y) / max(1, h - ground_y)
			c = base if t < 0.55 else dark
			if rng.random() < density:
				c = hi if rng.random() < 0.5 else dark
			set_px(img, x, y, c)
	# tips above ground line
	for x in range(w):
		height = tip_amp + int(rng.random() * tip_amp * 1.4)
		# occasional taller blade
		if rng.random() < 0.12:
			height += tip_amp
		for i in range(height):
			yy = ground_y - 1 - i
			c = hi if i % 2 == 0 else dark
			set_px(img, x, yy, c)
			if rng.random() < 0.3 and x + 1 < w:
				set_px(img, x + 1, yy, c)


def widget_fairway():
	img = new_img(256, 96)
	rng = random.Random(10)
	w, h = img.size
	ground_y = int(h * 0.55)
	for y in range(ground_y, h):
		for x in range(w):
			# mow stripes ~ every 3 px vertical bands? horizontal mow
			band = (y // 2) % 2
			c = FW_MID if band == 0 else FW_LIGHT
			if rng.random() < 0.08:
				c = FW_DARK
			set_px(img, x, y, c)
	# short tidy tips
	for x in range(w):
		hgt = 1 + (1 if rng.random() < 0.35 else 0)
		for i in range(hgt):
			set_px(img, x, ground_y - 1 - i, FW_LIGHT if i == 0 else FW_MID)
	return img


def widget_green():
	img = new_img(256, 96)
	rng = random.Random(11)
	w, h = img.size
	ground_y = int(h * 0.55)
	for y in range(ground_y, h):
		for x in range(w):
			c = GN_MID
			if rng.random() < 0.04:
				c = GN_LIGHT
			set_px(img, x, y, c)
	# almost flat top — putting surface
	for x in range(w):
		set_px(img, x, ground_y - 1, GN_LIGHT if x % 3 == 0 else GN_MID)
	return img


def widget_rough():
	img = new_img(256, 96)
	rng = random.Random(12)
	_grass_strip(img, RG_GROUND, RG_HI, RG_DARK, tip_amp=4, rng=rng, density=0.25)
	return img


def widget_sand():
	img = new_img(256, 96)
	rng = random.Random(13)
	w, h = img.size
	ground_y = int(h * 0.50)
	# soft dune silhouette
	for x in range(w):
		wave = int(3 * __import__("math").sin(x * 0.08) + 2 * __import__("math").sin(x * 0.03))
		top = ground_y + wave
		for y in range(top, h):
			t = (y - top) / max(1, h - top)
			c = SAND_L if t < 0.25 else (SAND_M if t < 0.65 else SAND_D)
			if rng.random() < 0.1:
				c = SAND_L
			set_px(img, x, y, c)
	return img


def widget_tee():
	img = new_img(256, 96)
	rng = random.Random(14)
	w, h = img.size
	ground_y = int(h * 0.55)
	for y in range(ground_y, h):
		for x in range(w):
			band = (y // 2) % 2
			c = TEE_BOX if band == 0 else FW_MID
			if rng.random() < 0.06:
				c = FW_DARK
			set_px(img, x, y, c)
	# short mown tips
	for x in range(w):
		set_px(img, x, ground_y - 1, FW_LIGHT if x % 2 == 0 else TEE_BOX)
	return img


def widget_ball():
	img = new_img(32, 32)
	draw_ball(img, 15, 15, 12)
	outline_nonzero(img)
	return img


def widget_tee_peg():
	img = new_img(16, 24)
	# narrow peg
	fill_rect(img, 6, 6, 9, 22, TEE_PEG)
	fill_rect(img, 7, 6, 8, 22, TEE_PEG_D)
	fill_rect(img, 4, 4, 11, 7, TEE_PEG)
	fill_rect(img, 5, 3, 10, 4, TEE_PEG)
	outline_nonzero(img)
	return img


def main() -> None:
	makers = {
		"lie_fairway": lie_fairway,
		"lie_green": lie_green,
		"lie_rough": lie_rough,
		"lie_sand": lie_sand,
		"lie_tee": lie_tee,
		"lie_widget_fairway": widget_fairway,
		"lie_widget_green": widget_green,
		"lie_widget_rough": widget_rough,
		"lie_widget_sand": widget_sand,
		"lie_widget_tee": widget_tee,
		"lie_widget_ball": widget_ball,
		"lie_widget_tee_peg": widget_tee_peg,
	}
	for name, fn in makers.items():
		im = fn()
		im.save(OUT / f"{name}.png")
		print("wrote", name, im.size)

	# glance strip
	glance = ["lie_tee", "lie_fairway", "lie_rough", "lie_sand", "lie_green"]
	sheet = Image.new("RGBA", (4 + 68 * len(glance), 72), (30, 34, 30, 255))
	for i, name in enumerate(glance):
		im = Image.open(OUT / f"{name}.png")
		sheet.paste(im, (4 + i * 68, 4), im)
	sheet.save(OUT / "wave_C_lie_glance_strip.png")
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
		OUT / "wave_C_lie_glance_strip_x2.png"
	)

	# widget strip (scaled down for overview)
	widgets = [
		"lie_widget_tee",
		"lie_widget_fairway",
		"lie_widget_rough",
		"lie_widget_sand",
		"lie_widget_green",
	]
	ww, wh = 256, 96
	wsheet = Image.new("RGBA", (8 + (ww + 8) * len(widgets), wh + 16), (20, 24, 20, 255))
	for i, name in enumerate(widgets):
		im = Image.open(OUT / f"{name}.png")
		wsheet.paste(im, (8 + i * (ww + 8), 8), im)
	wsheet.save(OUT / "wave_C_lie_widget_strip.png")
	print("strips ok")


if __name__ == "__main__":
	main()
