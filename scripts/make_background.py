#!/usr/bin/env python3
"""Generate the PenguinVault boot-menu background.

Deep polar-night gradient with an aurora wash, a faint vault-door ring behind
the menu area, and a small Tux-ish penguin mark. Everything is drawn, so there
are no external image assets to ship.

Usage: make_background.py OUT.png [WIDTH HEIGHT]
"""
import math
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W = int(sys.argv[2]) if len(sys.argv) > 2 else 1920
H = int(sys.argv[3]) if len(sys.argv) > 3 else 1080
OUT = sys.argv[1] if len(sys.argv) > 1 else "background.png"

# Polar-night palette. Kept light enough that the artwork still reads on a
# dim projector or a washed-out laptop panel — a boot menu that looks like a
# black screen reads as broken, not stylish.
TOP = (10, 20, 34)
MID = (24, 48, 74)
BOT = (6, 12, 22)
ICE = (72, 202, 228)
AMBER = (255, 183, 3)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


img = Image.new("RGB", (W, H), TOP)
d = ImageDraw.Draw(img)

# Vertical gradient, TOP -> MID -> BOT.
for y in range(H):
    t = y / (H - 1)
    if t < 0.55:
        c = lerp(TOP, MID, t / 0.55)
    else:
        c = lerp(MID, BOT, (t - 0.55) / 0.45)
    d.line([(0, y), (W, y)], fill=c)

# Glows are screened (added) onto the base rather than blended into it —
# blending averages toward the darker layer and washes the whole frame out.
def glow(layer, blur, strength):
    """Screen a blurred layer over img at `strength` (0-1)."""
    global img
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    if strength < 1.0:
        layer = Image.eval(layer, lambda v: int(v * strength))
    img = ImageChops.screen(img, layer)


# Aurora: soft ice-coloured bands drifting across the upper third.
aurora = Image.new("RGB", (W, H), (0, 0, 0))
ad = ImageDraw.Draw(aurora)
for i, (y0, amp, alpha) in enumerate(((0.30, 60, 150), (0.38, 90, 105), (0.24, 40, 80))):
    pts = []
    for x in range(0, W + 1, 8):
        p = x / W
        y = y0 * H + math.sin(p * math.pi * (1.6 + i * 0.7) + i) * amp
        pts.append((x, y))
    pts += [(W, 0), (0, 0)]
    ad.polygon(pts, fill=tuple(c * alpha // 255 for c in ICE))
glow(aurora, 70, 0.55)

# Vault door: concentric rings and spokes centred behind the menu.
vault = Image.new("RGB", (W, H), (0, 0, 0))
vd = ImageDraw.Draw(vault)
cx, cy = int(W * 0.5), int(H * 0.52)
for r, wdt, a in ((int(H * 0.40), 3, 120), (int(H * 0.33), 2, 92), (int(H * 0.26), 2, 70)):
    vd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=tuple(c * a // 255 for c in ICE), width=wdt)
for ang in range(0, 360, 45):
    a = math.radians(ang)
    r0, r1 = int(H * 0.26), int(H * 0.40)
    vd.line(
        [cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + r1 * math.cos(a), cy + r1 * math.sin(a)],
        fill=tuple(c * 70 // 255 for c in ICE), width=2,
    )
glow(vault, 3, 0.5)
d = ImageDraw.Draw(img)

# Penguin mark, bottom-right: simple geometric silhouette, understated.
px, py, s = int(W * 0.895), int(H * 0.80), H * 0.115
body = [
    (px, py - s),
    (px + s * 0.42, py - s * 0.45),
    (px + s * 0.46, py + s * 0.35),
    (px + s * 0.30, py + s * 0.62),
    (px - s * 0.30, py + s * 0.62),
    (px - s * 0.46, py + s * 0.35),
    (px - s * 0.42, py - s * 0.45),
]
d.polygon(body, fill=(9, 17, 28))
d.polygon(
    [
        (px, py - s * 0.72),
        (px + s * 0.28, py - s * 0.20),
        (px + s * 0.30, py + s * 0.34),
        (px, py + s * 0.50),
        (px - s * 0.30, py + s * 0.34),
        (px - s * 0.28, py - s * 0.20),
    ],
    fill=(22, 40, 60),
)
# Eyes + beak.
d.ellipse([px - s * 0.20, py - s * 0.62, px - s * 0.06, py - s * 0.44], fill=(200, 226, 240))
d.ellipse([px + s * 0.06, py - s * 0.62, px + s * 0.20, py - s * 0.44], fill=(200, 226, 240))
d.ellipse([px - s * 0.16, py - s * 0.58, px - s * 0.10, py - s * 0.50], fill=(6, 12, 20))
d.ellipse([px + s * 0.10, py - s * 0.58, px + s * 0.16, py - s * 0.50], fill=(6, 12, 20))
d.polygon([(px - s * 0.09, py - s * 0.40), (px + s * 0.09, py - s * 0.40), (px, py - s * 0.26)], fill=AMBER)
# Feet.
d.polygon([(px - s * 0.26, py + s * 0.62), (px - s * 0.02, py + s * 0.62), (px - s * 0.14, py + s * 0.74)], fill=AMBER)
d.polygon([(px + s * 0.02, py + s * 0.62), (px + s * 0.26, py + s * 0.62), (px + s * 0.14, py + s * 0.74)], fill=AMBER)

# Thin ice rule dividing the wordmark block from the menu. Sits at 19.5%:
# below the subtitle (theme.txt puts it at 15%) and above the first menu
# item (23%). Putting it at ~15% strikes straight through the subtitle text.
d.rectangle([int(W * 0.06), int(H * 0.195), int(W * 0.06) + int(W * 0.14), int(H * 0.195) + 3], fill=ICE)

# Gentle vignette. The darkened edge is only a little below the base tone —
# a hard vignette is what turned the first attempt into a black rectangle.
vig = Image.new("L", (W, H), 0)
vd2 = ImageDraw.Draw(vig)
vd2.ellipse([-int(W * 0.45), -int(H * 0.60), int(W * 1.45), int(H * 1.60)], fill=255)
vig = vig.filter(ImageFilter.GaussianBlur(220))
img = Image.composite(img, Image.eval(img, lambda v: int(v * 0.55)), vig)

img.save(OUT, "PNG", optimize=True)
print(f"wrote {OUT} ({W}x{H})")
