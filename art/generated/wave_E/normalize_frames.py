"""Plant Wave E south-east poses on 128x192 with shared cap-to-feet scale."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
ALL = ROOT / "char_states" / "all"
OUT = ROOT / "norm"
POSES = [
    ("address", "swing_address"),
    ("takeaway", "swing_takeaway"),
    ("mid", "swing_mid"),
    ("late", "swing_late"),
    ("top", "swing_top"),
    ("early_down", "swing_early_down"),
    ("impact", "swing_impact"),
    ("follow", "swing_follow"),
]
CANVAS = (128, 192)
FEET_Y = 178
BODY_H = 90  # cap-top to feet, same on every frame
VIEW = "south-east"


def is_olive(r: int, g: int, b: int, a: int) -> bool:
    return a >= 128 and 70 <= g <= 130 and 60 <= r <= 120 and b < g - 12


def is_skin(r: int, g: int, b: int, a: int) -> bool:
    return a >= 128 and r > 180 and g > 130 and b > 90 and r >= g and r > b + 20


def _olive_pixels(im: Image.Image) -> list[tuple[int, int]]:
    px = im.load()
    w, h = im.size
    return [(x, y) for y in range(h) for x in range(w) if is_olive(*px[x, y])]


def _cap_blob(im: Image.Image) -> list[tuple[int, int]]:
    """Largest olive blob is the cap; club head is a smaller blob higher up."""
    pts = _olive_pixels(im)
    if not pts:
        return []
    seen: set[tuple[int, int]] = set()
    best: list[tuple[int, int]] = []
    pset = set(pts)
    for start in pts:
        if start in seen:
            continue
        blob: list[tuple[int, int]] = []
        stack = [start]
        seen.add(start)
        while stack:
            x, y = stack.pop()
            blob.append((x, y))
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if (nx, ny) in pset and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    stack.append((nx, ny))
        if len(blob) > len(best):
            best = blob
    return best


def cap_top(im: Image.Image) -> int:
    blob = _cap_blob(im)
    if blob:
        return min(y for _, y in blob)
    skin = [y for y in range(im.size[1]) for x in range(im.size[0]) if is_skin(*im.getpixel((x, y)))]
    if not skin:
        return im.getbbox()[1]
    hist = [0] * im.size[1]
    for y in skin:
        hist[y] += 1
    lo = int(im.size[1] * 0.30)
    band = max(range(lo, im.size[1]), key=lambda y: hist[y])
    return max(0, band - 10)


def cap_x(im: Image.Image) -> int:
    blob = _cap_blob(im)
    if not blob:
        bb = im.getbbox()
        return (bb[0] + bb[2]) // 2
    return round(sum(x for x, _ in blob) / len(blob))


def feet_y(im: Image.Image) -> int:
    bb = im.getbbox()
    return bb[3] - 1


def feet_x(im: Image.Image, fy: int) -> int:
    px = im.load()
    xs = [x for x in range(im.size[0]) if px[x, fy][3] >= 128]
    if not xs:
        bb = im.getbbox()
        return (bb[0] + bb[2]) // 2
    return (min(xs) + max(xs)) // 2


def plant(im: Image.Image) -> Image.Image:
    cap = cap_top(im)
    fy = feet_y(im)
    body = max(fy - cap, 1)
    scale = BODY_H / body
    nw = max(1, round(im.size[0] * scale))
    nh = max(1, round(im.size[1] * scale))
    scaled = im.resize((nw, nh), Image.NEAREST)
    fy2 = round(fy * scale)
    # Club on the ground poisons feet_x (putt address vs takeaway slides the body).
    cx2 = round(cap_x(im) * scale)
    canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    paste = (CANVAS[0] // 2 - cx2, FEET_Y - fy2)
    canvas.alpha_composite(scaled, paste)
    return canvas


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    frames = []
    for pose, folder in POSES:
        im = Image.open(ALL / folder / "rotations" / f"{VIEW}.png").convert("RGBA")
        out = plant(im)
        dest = OUT / f"ui_golfer_{pose}.png"
        out.save(dest)
        cap, fy = cap_top(out), feet_y(out)
        print(f"{pose:12} {out.size} cap={cap} feet={fy} body={fy - cap}")
        assert out.size == CANVAS
        assert abs(fy - FEET_Y) <= 1, pose
        assert abs((fy - cap) - BODY_H) <= 5, pose
        frames.append(out)
    w, h = CANVAS
    strip = Image.new("RGBA", (w * 8 * 2, h * 2), (16, 20, 16, 255))
    for i, im in enumerate(frames):
        big = im.resize((w * 2, h * 2), Image.NEAREST)
        strip.paste(big, (i * w * 2, 0), big)
    sdest = ROOT / "char_states_norm_strip_x2.png"
    strip.save(sdest)
    print("strip", sdest)


if __name__ == "__main__":
    main()
