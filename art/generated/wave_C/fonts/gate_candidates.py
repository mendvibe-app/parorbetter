#!/usr/bin/env python3
"""Digit ink check + gate sheets for free font candidates."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).parent / "candidates"
out = Path(__file__).parent
fonts = {
	"PixelifySans (live)": root / "PixelifySans-Regular.ttf",
	"PublicPixel CC0": root / "public_pixel" / "PublicPixel.ttf",
	"PixelOperator CC0": root / "pixel_operator" / "PixelOperator.ttf",
	"PixelOperatorMono CC0": root / "pixel_operator" / "PixelOperatorMono.ttf",
	"VT323 OFL": root / "VT323-Regular.ttf",
	"PressStart2P OFL": root / "PressStart2P-Regular.ttf",
}
lines = [
	"0123456789",
	"5S 0O 1Il 8B 6g9",
	"Yardage 185  PAR 4",
	"3:1  2:1  72  -4  lives",
]


def ink(font: ImageFont.FreeTypeFont, ch: str) -> int:
	im = Image.new("L", (64, 48), 0)
	d = ImageDraw.Draw(im)
	d.text((2, 2), ch, font=font, fill=255)
	return sum(1 for p in im.getdata() if p > 0)


def main() -> None:
	print("=== DIGIT INK @32px ===")
	for name, path in fonts.items():
		if not path.is_file():
			print(name, "MISSING")
			continue
		font = ImageFont.truetype(str(path), 32)
		bad = [ch for ch in "0123456789" if ink(font, ch) < 8]
		print(f"{name:28} digits_ok={not bad}  bad={bad or '-'}")

	# comparison grid
	px = 40
	blocks: list[Image.Image] = []
	for name, path in fonts.items():
		font = ImageFont.truetype(str(path), px)
		dummy = Image.new("RGBA", (8, 8))
		d = ImageDraw.Draw(dummy)
		max_w = 420
		th = 28
		for line in [name] + lines:
			bb = d.textbbox((0, 0), line, font=font)
			max_w = max(max_w, bb[2] - bb[0])
			th += max(bb[3] - bb[1], px // 2) + 6
		img = Image.new("RGBA", (max_w + 24, th + 16), (24, 28, 24, 255))
		d = ImageDraw.Draw(img)
		y = 8
		d.text((12, y), name, font=font, fill=(160, 190, 130, 255))
		y += px + 4
		for line in lines:
			d.text((12, y), line, font=font, fill=(240, 242, 235, 255))
			bb = d.textbbox((0, 0), line, font=font)
			y += max(bb[3] - bb[1], int(px * 0.7)) + 6
		blocks.append(img)

	cols = 2
	w = max(b.width for b in blocks)
	h = max(b.height for b in blocks)
	rows = (len(blocks) + cols - 1) // cols
	sheet = Image.new("RGBA", (w * cols + 16, h * rows + 16), (18, 20, 18, 255))
	for i, b in enumerate(blocks):
		r, c = divmod(i, cols)
		sheet.paste(b, (8 + c * w, 8 + r * h))
	sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(
		out / "font_candidates_gate_x2.png"
	)
	print("wrote font_candidates_gate_x2.png")

	# digit focus strip
	focus = [
		"PixelifySans (live)",
		"PublicPixel CC0",
		"PixelOperator CC0",
		"PixelOperatorMono CC0",
		"VT323 OFL",
	]
	px = 32
	parts: list[Image.Image] = []
	lines2 = ["0123456789", "5S 0O 1Il 8B", "185 yd  PAR 4", "72  -3  3:1"]
	for name in focus:
		font = ImageFont.truetype(str(fonts[name]), px)
		dummy = Image.new("RGBA", (8, 8))
		d = ImageDraw.Draw(dummy)
		mw = 0
		th = 20
		for line in [name] + lines2:
			bb = d.textbbox((0, 0), line, font=font)
			mw = max(mw, bb[2] - bb[0])
			th += max(bb[3] - bb[1], px) + 6
		img = Image.new("RGBA", (mw + 20, th + 12), (28, 32, 28, 255))
		d = ImageDraw.Draw(img)
		y = 6
		d.text((10, y), name, font=font, fill=(140, 170, 120, 255))
		y += px + 2
		for line in lines2:
			d.text((10, y), line, font=font, fill=(240, 242, 235, 255))
			bb = d.textbbox((0, 0), line, font=font)
			y += max(bb[3] - bb[1], px) + 6
		parts.append(img)
	sw = sum(p.width for p in parts) + 8 * (len(parts) + 1)
	sh = max(p.height for p in parts) + 16
	strip = Image.new("RGBA", (sw, sh), (20, 22, 20, 255))
	x = 8
	for p in parts:
		strip.paste(p, (x, 8))
		x += p.width + 8
	strip.resize((strip.width * 3, strip.height * 3), Image.NEAREST).save(
		out / "font_digit_compare_x3.png"
	)
	print("wrote font_digit_compare_x3.png")


if __name__ == "__main__":
	main()
