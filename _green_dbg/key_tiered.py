# One-off: key black bg -> alpha, crop, save as green_tiered.png
from PIL import Image, ImageDraw

SRC = r"C:\Users\mattb\.cursor\projects\c-Users-mattb-Desktop-paradedb-parorbetter\assets\green_tiered_new.png"
DST = r"c:\Users\mattb\Desktop\paradedb\parorbetter\assets\greens\green_tiered.png"

img = Image.open(SRC).convert("RGBA")
key = (255, 0, 255, 255)
w, h = img.size
# ponytail: corner floodfill assumes bg is contiguous from corners; fine for one blob asset
for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
    ImageDraw.floodfill(img, xy, key, thresh=60)
px = img.load()
for y in range(h):
    for x in range(w):
        if px[x, y] == key:
            px[x, y] = (0, 0, 0, 0)
img = img.crop(img.getchannel("A").getbbox())
img.save(DST)

out = Image.open(DST)
a = out.getchannel("A")
assert a.getpixel((0, 0)) == 0 and a.getpixel((out.width - 1, out.height - 1)) == 0, "corners not transparent"
assert a.getpixel((out.width // 2, out.height // 2)) == 255, "center not opaque"
print("ok", out.size, out.mode)
