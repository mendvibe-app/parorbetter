#!/usr/bin/env python3
"""Hard-pixel Wave C HUD icons — Pixel Kit Golf (no soft AI silhouettes)."""

from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent

# STYLE.md anchors
OUTLINE = (26, 31, 26, 255)
SHAFT = (45, 48, 45, 255)
GRIP = (42, 58, 40, 255)
GRIP_RING = (90, 110, 70, 255)
WOOD_LIGHT = (186, 152, 107, 255)
WOOD_MID = (139, 107, 69, 255)
WOOD_DARK = (90, 70, 45, 255)
STEEL = (180, 190, 195, 255)
STEEL_DARK = (110, 120, 125, 255)
STEEL_HI = (220, 228, 230, 255)
LIFE_R = (200, 70, 70, 255)
LIFE_EMPTY = (70, 78, 70, 255)
BTN = (84, 126, 61, 255)
BTN_HI = (122, 154, 80, 255)


def new_img(w=64, h=64):
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
			nx = (x - cx) / max(rx, 1)
			ny = (y - cy) / max(ry, 1)
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


def draw_shaft(img, x, y0, y1, thick=2):
	fill_rect(img, x, y0, x + thick - 1, y1 - 10, SHAFT)
	fill_rect(img, x - 1, y1 - 9, x + thick, y1, GRIP)
	for gy in (y1 - 7, y1 - 4):
		fill_rect(img, x - 1, gy, x + thick, gy, GRIP_RING)


def club_driver():
	img = new_img()
	fill_ellipse(img, 28, 16, 16, 11, WOOD_MID)
	fill_ellipse(img, 26, 14, 10, 7, WOOD_LIGHT)
	fill_rect(img, 36, 18, 42, 22, WOOD_DARK)
	draw_shaft(img, 38, 22, 58, 2)
	outline_nonzero(img)
	return img


def club_wood():
	img = new_img()
	fill_ellipse(img, 30, 18, 13, 10, WOOD_MID)
	fill_ellipse(img, 28, 16, 8, 6, WOOD_LIGHT)
	fill_rect(img, 36, 20, 41, 24, WOOD_DARK)
	draw_shaft(img, 37, 24, 58, 2)
	outline_nonzero(img)
	return img


def club_hybrid():
	img = new_img()
	fill_ellipse(img, 32, 18, 11, 9, WOOD_MID)
	fill_rect(img, 28, 14, 40, 24, STEEL)
	fill_rect(img, 29, 15, 35, 22, STEEL_HI)
	fill_rect(img, 37, 20, 41, 24, STEEL_DARK)
	draw_shaft(img, 37, 24, 58, 2)
	outline_nonzero(img)
	return img


def club_iron():
	img = new_img()
	for y in range(12, 26):
		t = (y - 12) / 14.0
		left = int(24 + t * 2)
		right = int(42 - t * 4)
		fill_rect(img, left, y, right, y, STEEL if y > 14 else STEEL_HI)
	fill_rect(img, 36, 22, 40, 26, STEEL_DARK)
	draw_shaft(img, 37, 26, 58, 2)
	outline_nonzero(img)
	return img


def club_wedge():
	img = new_img()
	for y in range(10, 28):
		t = (y - 10) / 18.0
		left = int(22 + t * 6)
		right = int(40 - t * 2)
		c = STEEL_HI if y < 16 else STEEL
		fill_rect(img, left, y, right, y, c)
	fill_rect(img, 28, 26, 40, 28, STEEL_DARK)
	fill_rect(img, 36, 24, 40, 28, STEEL_DARK)
	draw_shaft(img, 37, 28, 58, 2)
	outline_nonzero(img)
	return img


def club_putter():
	img = new_img()
	fill_rect(img, 18, 16, 46, 24, STEEL)
	fill_rect(img, 20, 17, 44, 20, STEEL_HI)
	fill_rect(img, 30, 14, 34, 16, STEEL_DARK)
	draw_shaft(img, 31, 16, 58, 2)
	outline_nonzero(img)
	return img


def life_full():
	img = new_img()
	heart = [
		"..##..##..",
		".####.####.",
		"###########",
		"###########",
		".#########.",
		"..#######..",
		"...#####...",
		"....###....",
		".....#.....",
	]
	scale = 3
	ox, oy = 17, 16
	for j, row in enumerate(heart):
		for i, ch in enumerate(row):
			if ch != "#":
				continue
			for dy in range(scale):
				for dx in range(scale):
					set_px(img, ox + i * scale + dx, oy + j * scale + dy, LIFE_R)
	for j in range(2):
		for i in range(3):
			fill_rect(
				img,
				ox + (1 + i) * scale,
				oy + j * scale,
				ox + (1 + i) * scale + scale - 1,
				oy + j * scale + scale - 1,
				(230, 120, 120, 255),
			)
	outline_nonzero(img)
	return img


def life_empty():
	img = new_img()
	heart = [
		"..##..##..",
		".####.####.",
		"###########",
		"###########",
		".#########.",
		"..#######..",
		"...#####...",
		"....###....",
		".....#.....",
	]
	scale = 3
	ox, oy = 17, 16
	tmp = new_img()
	for j, row in enumerate(heart):
		for i, ch in enumerate(row):
			if ch != "#":
				continue
			for dy in range(scale):
				for dx in range(scale):
					set_px(tmp, ox + i * scale + dx, oy + j * scale + dy, LIFE_EMPTY)
	w, h = tmp.size
	for y in range(h):
		for x in range(w):
			if tmp.getpixel((x, y))[3] == 0:
				continue
			edge = False
			for dy in (-1, 0, 1):
				for dx in (-1, 0, 1):
					nx, ny = x + dx, y + dy
					if not (0 <= nx < w and 0 <= ny < h) or tmp.getpixel((nx, ny))[3] == 0:
						edge = True
			if edge:
				set_px(img, x, y, LIFE_EMPTY)
	outline_nonzero(img, (40, 45, 40, 255))
	return img


def confirm_aim():
	img = new_img()
	for i in range(18):
		fill_rect(img, 12 + i, 18 + i // 2, 12 + i + 6, 18 + i // 2 + 5, BTN)
		fill_rect(img, 12 + i, 40 - i // 2, 12 + i + 6, 40 - i // 2 + 5, BTN)
	for y in range(22, 42):
		t = abs(y - 32) / 10.0
		x0 = 18 + int((1 - t) * 20)
		fill_rect(img, x0, y, x0 + 8, y, BTN_HI if y < 32 else BTN)
	outline_nonzero(img)
	return img


def confirm_aim_pressed():
	img = confirm_aim()
	w, h = img.size
	for y in range(h):
		for x in range(w):
			r, g, b, a = img.getpixel((x, y))
			if a and (r, g, b) != OUTLINE[:3]:
				img.putpixel((x, y), (max(0, r - 40), max(0, g - 40), max(0, b - 30), a))
	return img


def main() -> None:
	makers = {
		"club_driver": club_driver,
		"club_wood": club_wood,
		"club_hybrid": club_hybrid,
		"club_iron": club_iron,
		"club_wedge": club_wedge,
		"club_putter": club_putter,
		"life_full": life_full,
		"life_empty": life_empty,
		"confirm_aim_button": confirm_aim,
		"confirm_aim_button_pressed": confirm_aim_pressed,
	}
	for name, fn in makers.items():
		im = fn()
		im.save(OUT / f"{name}.png")
		print("wrote", name)

	names = list(makers.keys())
	sheet = Image.new("RGBA", (64 * len(names) + 4 * (len(names) + 1), 72), (30, 34, 30, 255))
	for i, name in enumerate(names):
		im = Image.open(OUT / f"{name}.png")
		sheet.paste(im, (4 + i * 68, 4), im)
	sheet.save(OUT / "wave_C_hud_strip.png")
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(OUT / "wave_C_hud_strip_x2.png")
	print("wave_C_hud strip ok")


if __name__ == "__main__":
	main()
