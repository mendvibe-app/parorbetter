#!/usr/bin/env python3
"""Hard-pixel club HEADS for pad drag cursor (no long shaft)."""

from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent
OUTLINE = (26, 31, 26, 255)
WOOD = (139, 107, 69, 255)
WOOD_L = (186, 152, 107, 255)
WOOD_D = (90, 70, 45, 255)
STEEL = (190, 198, 205, 255)
STEEL_L = (230, 235, 238, 255)
STEEL_D = (110, 120, 128, 255)
HOSEL = (55, 58, 55, 255)


def new_img(w=48, h=48):
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


def head_driver():
	"""Pear wood head, face right — pad cursor."""
	img = new_img()
	fill_ellipse(img, 22, 24, 16, 12, WOOD)
	fill_ellipse(img, 20, 22, 10, 8, WOOD_L)
	fill_ellipse(img, 28, 26, 6, 8, WOOD_D)  # sole/face shade
	# face stripe
	fill_rect(img, 30, 16, 33, 32, STEEL_L)
	# short hosel stub up
	fill_rect(img, 18, 10, 22, 16, HOSEL)
	outline_nonzero(img)
	return img


def head_iron():
	"""Blade face right."""
	img = new_img()
	# blade trapezoid
	for y in range(14, 36):
		t = (y - 14) / 22.0
		left = int(12 + t * 4)
		right = int(34 - t * 6)
		c = STEEL_L if y < 20 else STEEL
		fill_rect(img, left, y, right, y, c)
	fill_rect(img, 28, 28, 34, 36, STEEL_D)  # sole
	# grooves
	for gy in range(18, 30, 3):
		fill_rect(img, 16, gy, 28, gy, STEEL_D)
	fill_rect(img, 20, 10, 24, 16, HOSEL)
	outline_nonzero(img)
	return img


def head_putter():
	"""Blade putter face, short head."""
	img = new_img()
	fill_rect(img, 10, 18, 38, 30, STEEL)
	fill_rect(img, 12, 19, 36, 24, STEEL_L)
	fill_rect(img, 14, 26, 34, 29, STEEL_D)
	# alignment line
	fill_rect(img, 23, 16, 25, 32, (255, 80, 80, 255))
	fill_rect(img, 22, 12, 26, 18, HOSEL)
	outline_nonzero(img)
	return img


def head_wood():
	"""Fairway wood — smaller pear than driver, shallower face."""
	img = new_img()
	fill_ellipse(img, 24, 25, 13, 10, WOOD)
	fill_ellipse(img, 22, 23, 8, 6, WOOD_L)
	fill_ellipse(img, 28, 27, 5, 6, WOOD_D)
	fill_rect(img, 30, 18, 32, 30, STEEL_L)
	fill_rect(img, 20, 12, 24, 18, HOSEL)
	outline_nonzero(img)
	return img


def head_hybrid():
	"""Hybrid — half wood body + iron face."""
	img = new_img()
	fill_ellipse(img, 22, 25, 11, 9, WOOD)
	fill_ellipse(img, 20, 23, 6, 5, WOOD_L)
	# iron-ish face plate
	for y in range(16, 34):
		t = (y - 16) / 18.0
		left = int(24 + t * 2)
		right = int(34 - t * 3)
		fill_rect(img, left, y, right, y, STEEL_L if y < 22 else STEEL)
	fill_rect(img, 18, 11, 22, 17, HOSEL)
	outline_nonzero(img)
	return img


def head_wedge():
	"""Wedge — lofted thick sole blade."""
	img = new_img()
	for y in range(12, 36):
		t = (y - 12) / 24.0
		left = int(10 + t * 8)
		right = int(32 - t * 2)
		c = STEEL_L if y < 18 else STEEL
		fill_rect(img, left, y, right, y, c)
	# wide flange / bounce
	fill_rect(img, 18, 32, 36, 38, STEEL_D)
	fill_rect(img, 20, 30, 34, 34, STEEL_D)
	# grooves
	for gy in range(16, 28, 3):
		fill_rect(img, 16, gy, 28, gy, STEEL_D)
	fill_rect(img, 18, 8, 22, 14, HOSEL)
	outline_nonzero(img)
	return img


def main() -> None:
	makers = {
		"ui_club_head_driver": head_driver,
		"ui_club_head_wood": head_wood,
		"ui_club_head_hybrid": head_hybrid,
		"ui_club_head_iron": head_iron,
		"ui_club_head_wedge": head_wedge,
		"ui_club_head_putter": head_putter,
	}
	for name, fn in makers.items():
		im = fn()
		im.save(OUT / f"{name}.png")
		print("wrote", name)
	sheet = Image.new("RGBA", (48 * len(makers) + 16, 56), (30, 34, 30, 255))
	for i, name in enumerate(makers):
		im = Image.open(OUT / f"{name}.png")
		sheet.paste(im, (8 + i * 52, 4), im)
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
		OUT / "wave_C_club_heads_x2.png"
	)


if __name__ == "__main__":
	main()
