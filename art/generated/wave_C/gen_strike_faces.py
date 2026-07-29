#!/usr/bin/env python3
"""Hard-pixel strike map faces — wood / iron / putter (Pixel Kit Golf)."""

from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent
OUTLINE = (20, 22, 20, 255)
FACE = (48, 52, 50, 255)
FACE_HI = (70, 74, 72, 255)
FACE_LO = (32, 36, 34, 255)
GROOVE = (28, 30, 28, 255)
HOSEL = (40, 42, 40, 255)
SWEET = (180, 150, 90, 255)
ALIGN = (100, 180, 210, 255)


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


def outline_nonzero(img):
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
						set_px(img, x, y, OUTLINE)
						break


def in_ellipse(x, y, cx, cy, rx, ry):
	nx = (x - cx) / max(rx, 0.001)
	ny = (y - cy) / max(ry, 0.001)
	return nx * nx + ny * ny <= 1.0


def strike_wood():
	# 128×110 — pear/oval face + hosel top-left
	img = new_img(128, 110)
	cx, cy, rx, ry = 68, 58, 50, 40
	fill_ellipse(img, cx, cy, rx, ry, FACE)
	# subtle face gradient bands
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if not in_ellipse(x, y, cx, cy, rx, ry):
				continue
			if y < cy - 8:
				set_px(img, x, y, FACE_HI)
			elif y > cy + 12:
				set_px(img, x, y, FACE_LO)
	# grooves (horizontal, clipped to oval)
	for gy in range(cy - 22, cy + 24, 5):
		for x in range(cx - rx + 8, cx + rx - 8):
			if in_ellipse(x, gy, cx, cy, rx - 2, ry - 2):
				set_px(img, x, gy, GROOVE)
	# sweet-spot mark
	fill_ellipse(img, cx, cy, 4, 4, SWEET)
	fill_ellipse(img, cx, cy, 2, 2, (220, 190, 120, 255))
	# hosel
	fill_rect(img, 18, 8, 28, 28, HOSEL)
	fill_rect(img, 22, 4, 30, 14, HOSEL)
	outline_nonzero(img)
	return img


def strike_iron():
	# 128×110 — rectangular face, hosel top-left
	img = new_img(128, 110)
	x0, y0, x1, y1 = 22, 22, 118, 96
	fill_rect(img, x0, y0, x1, y1, FACE)
	# top highlight band
	fill_rect(img, x0 + 2, y0 + 2, x1 - 2, y0 + 10, FACE_HI)
	fill_rect(img, x0 + 2, y1 - 10, x1 - 2, y1 - 2, FACE_LO)
	# grooves
	for gy in range(y0 + 14, y1 - 12, 5):
		fill_rect(img, x0 + 10, gy, x1 - 10, gy, GROOVE)
	# sweet spot
	fill_ellipse(img, (x0 + x1) // 2, (y0 + y1) // 2, 3, 3, SWEET)
	# hosel
	fill_rect(img, 12, 8, 24, 30, HOSEL)
	fill_rect(img, 16, 4, 26, 14, HOSEL)
	outline_nonzero(img)
	return img


def strike_putter():
	# 128×96 — flat blade, center alignment line
	img = new_img(128, 96)
	x0, y0, x1, y1 = 18, 24, 118, 82
	fill_rect(img, x0, y0, x1, y1, FACE)
	fill_rect(img, x0 + 2, y0 + 2, x1 - 2, y0 + 12, FACE_HI)
	fill_rect(img, x0 + 2, y1 - 10, x1 - 2, y1 - 2, FACE_LO)
	# fine face lines
	for gy in range(y0 + 16, y1 - 12, 4):
		fill_rect(img, x0 + 8, gy, x1 - 8, gy, GROOVE)
	# alignment
	mx = (x0 + x1) // 2
	fill_rect(img, mx - 1, y0 + 6, mx + 1, y1 - 6, ALIGN)
	# hosel stub top-center-left
	fill_rect(img, mx - 4, 8, mx + 4, 26, HOSEL)
	outline_nonzero(img)
	return img


def main() -> None:
	makers = {
		"strike_face_wood": strike_wood,
		"strike_face_iron": strike_iron,
		"strike_face_putter": strike_putter,
	}
	for name, fn in makers.items():
		im = fn()
		im.save(OUT / f"{name}.png")
		print("wrote", name, im.size)
	# strip
	sheet = Image.new("RGBA", (128 * 3 + 24, 120), (24, 28, 24, 255))
	for i, name in enumerate(makers):
		im = Image.open(OUT / f"{name}.png")
		sheet.paste(im, (8 + i * 136, (120 - im.height) // 2), im)
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
		OUT / "wave_C_strike_faces_x2.png"
	)


if __name__ == "__main__":
	main()
