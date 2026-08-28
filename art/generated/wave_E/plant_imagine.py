"""Knock out Imagine lock fills and plant on 128x192 using normalize_frames."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

import normalize_frames as nf

LOCK = Path(__file__).resolve().parent / "imagine" / "lock"
OUT = Path(__file__).resolve().parent / "imagine" / "norm"
POSES = [
    "address",
    "takeaway",
    "mid",
    "late",
    "top",
    "early_down",
    "impact",
    "follow",
]
PACKS = {
    "full": ("", "norm_strip_x2.png"),
    "putt": ("putt_", "norm_strip_putt_x2.png"),
    "chip": ("chip_", "norm_strip_chip_x2.png"),
}


def _is_white_bg(r: int, g: int, b: int, a: int) -> bool:
    """Near-neutral pale paper. Cream polo is high-chroma; silver club is darker."""
    if a < 1:
        return False
    mn, mx = min(r, g, b), max(r, g, b)
    return mn >= 240 and mx - mn <= 12


def knockout_white(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            if _is_white_bg(*px[x, y]):
                px[x, y] = (0, 0, 0, 0)
    return im


def opaque_count(im: Image.Image) -> int:
    return sum(1 for a in im.getdata(3) if a >= 128)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", choices=sorted(PACKS), default="full")
    args = ap.parse_args()
    prefix, strip_name = PACKS[args.pack]
    OUT.mkdir(parents=True, exist_ok=True)
    frames: list[Image.Image] = []
    for pose in POSES:
        src = LOCK / f"lock_{prefix}{pose}.png"
        im = knockout_white(Image.open(src))
        n = opaque_count(im)
        assert n > 800, f"{prefix}{pose} knockout ate the sprite ({n})"
        out = nf.plant(im)
        dest = OUT / f"ui_golfer_{prefix}{pose}.png"
        out.save(dest)
        cap, fy = nf.cap_top(out), nf.feet_y(out)
        print(f"{prefix}{pose:12} opaque={n:6} cap={cap:3} feet={fy:3} body={fy - cap}")
        assert out.size == nf.CANVAS
        assert abs(fy - nf.FEET_Y) <= 2, prefix + pose
        frames.append(out)
    cxs = [nf.cap_x(f) for f in frames]
    assert max(cxs) - min(cxs) <= 2, (prefix, cxs)
    w, h = nf.CANVAS
    strip = Image.new("RGBA", (w * 8 * 2, h * 2), (40, 48, 56, 255))
    for i, im in enumerate(frames):
        big = im.resize((w * 2, h * 2), Image.NEAREST)
        strip.paste(big, (i * w * 2, 0), big)
    sdest = Path(__file__).resolve().parent / "imagine" / strip_name
    strip.save(sdest)
    print("strip", sdest)


if __name__ == "__main__":
    main()
