#!/usr/bin/env python3
"""Hard-pixel tempo / putt / chip pad chrome — Pixel Kit Golf."""

from pathlib import Path
from PIL import Image

OUT = Path(__file__).resolve().parent
OUTLINE = (26, 31, 26, 255)

# Swing path = white motion corridor (not grass, not thin neon).
# Family only tints the edge whisper so modes still read apart at a glance.
W_CORE = (255, 255, 255, 255)
W_MID = (230, 232, 235, 255)
W_SOFT = (200, 204, 210, 255)
W_EDGE = (40, 44, 48, 255)  # dark rim so white holds on light pad chrome

# Landmark accents still family-colored (lane itself stays white-first).
T_LO = (50, 70, 40, 255)
T_MID = (84, 150, 70, 255)
T_HI = (140, 220, 100, 255)
T_ACC = (200, 255, 140, 255)

P_LO = (40, 70, 90, 255)
P_MID = (70, 140, 180, 255)
P_HI = (140, 210, 230, 255)
P_ACC = (210, 245, 255, 255)

C_LO = (90, 70, 45, 255)
C_MID = (200, 160, 100, 255)
C_HI = (230, 200, 140, 255)
C_ACC = (255, 230, 180, 255)


def new_img(w, h):
	return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def set_px(img, x, y, c):
	if 0 <= x < img.width and 0 <= y < img.height:
		img.putpixel((x, y), c)


def fill_rect(img, x0, y0, x1, y1, c):
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
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


def fill_ellipse(img, cx, cy, rx, ry, c):
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			nx = (x - cx) / max(rx, 0.001)
			ny = (y - cy) / max(ry, 0.001)
			if nx * nx + ny * ny <= 1.0:
				set_px(img, x, y, c)


def make_lane(edge_tint, seed_pat=0):
	"""64×128 white swing corridor — thick mobile-readable motion path.

	White path-of-stroke language (broadcast tracer / swing plane), not turf and
	not a thin neon. Optional cool/warm edge_tint only at the rim.
	"""
	img = new_img(64, 128)
	cx = 32
	# Use almost full texture width — draw scale multiplies this for fat on-pad read.
	half = 30
	for y in range(128):
		for x in range(64):
			dx = abs(x - cx)
			if dx > half:
				continue
			# Fluid alpha: translucent corridor, not a solid white bar.
			# Soft radial falloff + light vertical shimmer (motion, not slab).
			t = dx / float(half)  # 0 core → 1 rim
			a = int(150 * (1.0 - t * t) + 28)  # ~178 core → ~28 rim
			# Subtle pulse bands along the path (reads as flow)
			flow = 0.85 + 0.15 * (1.0 if ((y // 3) + seed_pat) % 4 != 0 else 0.0)
			a = int(a * flow)

			# Soft white — never pure opaque
			if dx <= 4:
				rgb = W_CORE
				a = min(a + 20, 190)
			elif dx <= 12:
				rgb = W_MID
			else:
				rgb = W_SOFT

			# Thin dark rim only — holds edge without killing fluidity
			if dx >= half - 2:
				rgb = W_EDGE
				a = min(a, 90)
			elif dx >= half - 5 and edge_tint is not None:
				rgb = edge_tint
				a = min(a, 70)

			set_px(img, x, y, (rgb[0], rgb[1], rgb[2], max(0, min(255, a))))

		# Soft motion chevrons — translucent direction cues, not solid stamps
		if y % 18 == 8:
			for i in range(9):
				aa = 120 - i * 10
				c = (255, 255, 255, max(40, aa))
				set_px(img, cx - i, y + i // 2, c)
				set_px(img, cx + i, y + i // 2, c)
	return img


def landmark_start(mid, hi, acc):
	"""Target ring — address / start."""
	img = new_img(64, 64)
	cx = cy = 32
	# outer ring
	for y in range(64):
		for x in range(64):
			d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
			if 18 <= d <= 24:
				set_px(img, x, y, mid if int(d) % 2 == 0 else hi)
			elif 12 <= d < 18:
				set_px(img, x, y, lo_from(mid))
	# inner solid
	fill_ellipse(img, cx, cy, 8, 8, acc)
	fill_ellipse(img, cx - 1, cy - 1, 3, 3, (255, 255, 255, 255))
	outline_nonzero(img)
	return img


def lo_from(mid):
	return (max(0, mid[0] - 30), max(0, mid[1] - 30), max(0, mid[2] - 25), 255)


def landmark_top(mid, hi, acc):
	"""Up chevron — top of backswing."""
	img = new_img(64, 64)
	# thick V pointing up (two arms)
	for i in range(22):
		# left arm
		fill_rect(img, 30 - i, 18 + i, 34 - i, 18 + i + 5, hi if i < 10 else mid)
		# right arm
		fill_rect(img, 30 + i, 18 + i, 34 + i, 18 + i + 5, hi if i < 10 else mid)
	# fill peak
	fill_rect(img, 28, 16, 35, 22, acc)
	outline_nonzero(img)
	return img


def landmark_through(mid, hi, acc):
	"""Diamond — impact / through."""
	img = new_img(64, 64)
	cx = cy = 32
	for y in range(64):
		for x in range(64):
			md = abs(x - cx) + abs(y - cy)
			if md <= 8:
				set_px(img, x, y, acc)
			elif md <= 16:
				set_px(img, x, y, hi)
			elif md <= 20:
				set_px(img, x, y, mid)
	outline_nonzero(img)
	return img


def landmark_follow(mid, hi, acc):
	"""Open ring / finish mark."""
	img = new_img(64, 64)
	cx = cy = 32
	for y in range(64):
		for x in range(64):
			d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
			if 14 <= d <= 20:
				set_px(img, x, y, hi if (x + y) % 2 == 0 else mid)
	# small tick at bottom (direction of finish)
	fill_rect(img, 30, 48, 33, 56, acc)
	outline_nonzero(img)
	return img


def coach_idle(mid, hi, acc):
	"""Takeaway cue — stack of small up-chevrons."""
	img = new_img(64, 64)

	def chev(cy, col, scale=1):
		for i in range(8 * scale):
			fill_rect(img, 32 - i, cy + i, 32 - i + 2 * scale, cy + i + scale, col)
			fill_rect(img, 30 + i, cy + i, 30 + i + 2 * scale, cy + i + scale, col)

	chev(12, acc, 1)
	chev(26, hi, 1)
	chev(40, mid, 1)
	outline_nonzero(img)
	return img


def meter_track():
	img = new_img(128, 32)
	for y in range(32):
		for x in range(128):
			# border
			if y < 3 or y > 28 or x < 3 or x > 124:
				set_px(img, x, y, T_LO)
			else:
				band = (x // 4) % 2
				c = T_MID if band == 0 else T_HI
				if y < 8:
					c = T_HI
				set_px(img, x, y, c)
	# center notch
	fill_rect(img, 60, 4, 67, 27, T_ACC)
	outline_nonzero(img)
	return img


def meter_needle():
	img = new_img(64, 64)
	fill_ellipse(img, 32, 32, 18, 18, T_MID)
	fill_ellipse(img, 32, 32, 12, 12, T_HI)
	fill_ellipse(img, 32, 32, 5, 5, T_ACC)
	# pointer notch top
	fill_rect(img, 30, 8, 33, 16, T_ACC)
	outline_nonzero(img)
	return img


def family(prefix, lo, mid, hi, acc, seed, lane_edge=None):
	out = {
		f"{prefix}_lane": make_lane(lane_edge, seed),
		f"{prefix}_landmark_start": landmark_start(mid, hi, acc),
		f"{prefix}_landmark_top": landmark_top(mid, hi, acc),
		f"{prefix}_landmark_through": landmark_through(mid, hi, acc),
		f"{prefix}_landmark_follow": landmark_follow(mid, hi, acc),
		f"{prefix}_coach_idle": coach_idle(mid, hi, acc),
	}
	return out


def main() -> None:
	all_imgs = {}
	# Lanes are white-first; tiny cool/warm rim only (landmarks keep family color).
	all_imgs.update(family("ui_tempo", T_LO, T_MID, T_HI, T_ACC, 0, lane_edge=(200, 220, 200, 255)))
	all_imgs.update(family("ui_putt", P_LO, P_MID, P_HI, P_ACC, 1, lane_edge=(180, 210, 230, 255)))
	all_imgs.update(family("ui_chip", C_LO, C_MID, C_HI, C_ACC, 2, lane_edge=(230, 210, 180, 255)))
	# chip has no follow in assets list but we generate for consistency; only promote existing names
	all_imgs["ui_tempo_meter_track"] = meter_track()
	all_imgs["ui_tempo_meter_needle"] = meter_needle()

	# chip set has no follow landmark live — skip writing follow for chip? still write, unused ok
	for name, im in all_imgs.items():
		# skip chip follow if not in engine — actually chip doesn't preload follow; writing is fine
		im.save(OUT / f"{name}.png")
		print("wrote", name, im.size)

	# overview strip: three lanes + three tops + three starts
	keys = [
		"ui_tempo_lane",
		"ui_putt_lane",
		"ui_chip_lane",
		"ui_tempo_landmark_start",
		"ui_tempo_landmark_top",
		"ui_tempo_landmark_through",
		"ui_tempo_coach_idle",
		"ui_putt_landmark_top",
		"ui_chip_landmark_top",
	]
	# lanes are 64x128 — scale to 32x64 for strip
	cells = []
	for k in keys:
		im = all_imgs[k]
		if im.height > 64:
			im = im.resize((32, 64), Image.NEAREST)
		else:
			im = im.resize((32, 32), Image.NEAREST) if im.width > 40 else im
		cells.append(im)
	total_w = sum(c.width + 4 for c in cells) + 4
	sheet = Image.new("RGBA", (total_w, 72), (24, 28, 24, 255))
	x = 4
	for c in cells:
		y = 4 if c.height >= 60 else 20
		sheet.paste(c, (x, y), c)
		x += c.width + 4
	sheet.save(OUT / "wave_C_pad_chrome_strip.png")
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
		OUT / "wave_C_pad_chrome_strip_x2.png"
	)
	print("strip ok")


if __name__ == "__main__":
	main()
