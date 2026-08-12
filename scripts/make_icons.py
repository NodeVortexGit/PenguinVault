#!/usr/bin/env python3
"""Generate the PenguinVault boot-menu icon set.

GRUB draws one icon per menu entry, looked up as <theme>/icons/<class>.png,
where <class> is the menu class Ventoy assigns (from the ISO filename, or from
a menu_class rule in ventoy.json).

These are deliberately simple geometric marks in each project's brand colour
rather than reproductions of their logos: they stay legible at 32px, they all
share one visual language so the menu looks like a single design, and nothing
here redistributes anyone's trademarked artwork.

Usage: make_icons.py OUTDIR [SIZE]
"""
import math
import os
import sys
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "icons"
S = int(sys.argv[2]) if len(sys.argv) > 2 else 64
SS = 4  # supersample factor for smooth edges

os.makedirs(OUT, exist_ok=True)

INK = (232, 240, 247, 255)


def new():
    img = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name):
    img.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, f"{name}.png"))


def disc(d, color, inset=0.06):
    a = S * SS * inset
    d.ellipse([a, a, S * SS - a, S * SS - a], fill=color)


def rounded(d, color, inset=0.06, r=0.22):
    a = S * SS * inset
    d.rounded_rectangle([a, a, S * SS - a, S * SS - a], radius=S * SS * r, fill=color)


def poly_regular(cx, cy, r, n, rot=0):
    return [
        (cx + r * math.cos(rot + i * 2 * math.pi / n), cy + r * math.sin(rot + i * 2 * math.pi / n))
        for i in range(n)
    ]


C = S * SS / 2

# class name -> (background colour, glyph drawing function)
def make(name, bg, glyph):
    img, d = new()
    rounded(d, bg)
    glyph(d)
    save(img, name)


def tri_up(d, col=INK, scale=0.30, dy=0.06):
    d.polygon(
        [(C, C - S * SS * scale + S * SS * dy),
         (C - S * SS * scale, C + S * SS * scale * 0.85 + S * SS * dy),
         (C + S * SS * scale, C + S * SS * scale * 0.85 + S * SS * dy)],
        fill=col,
    )


def swirl(d, col=INK):
    r = S * SS * 0.28
    d.arc([C - r, C - r, C + r, C + r], 120, 400, fill=col, width=int(S * SS * 0.10))
    d.ellipse([C + r * 0.20, C - r * 0.95, C + r * 0.62, C - r * 0.53], fill=col)


def ring_dots(d, col=INK):
    r = S * SS * 0.26
    d.ellipse([C - r, C - r, C + r, C + r], outline=col, width=int(S * SS * 0.075))
    for ang in (90, 210, 330):
        a = math.radians(ang)
        rr = S * SS * 0.085
        x, y = C + r * math.cos(a), C + r * math.sin(a)
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)


def letter_f(d, col=INK):
    w = int(S * SS * 0.085)
    d.line([C - S * SS * 0.10, C + S * SS * 0.26, C - S * SS * 0.10, C - S * SS * 0.14], fill=col, width=w)
    d.arc([C - S * SS * 0.10, C - S * SS * 0.30, C + S * SS * 0.24, C + S * SS * 0.02], 180, 360, fill=col, width=w)
    d.line([C - S * SS * 0.24, C + S * SS * 0.04, C + S * SS * 0.06, C + S * SS * 0.04], fill=col, width=w)


def leaf(d, col=INK):
    r = S * SS * 0.27
    d.pieslice([C - r, C - r, C + r, C + r], 200, 340, fill=col)
    d.pieslice([C - r, C - r * 0.2, C + r, C + r * 1.8], 200, 340, fill=col)


def shield(d, col=INK):
    w = S * SS * 0.25
    h = S * SS * 0.30
    d.polygon([(C, C - h), (C + w, C - h * 0.45), (C + w * 0.78, C + h * 0.72),
               (C, C + h), (C - w * 0.78, C + h * 0.72), (C - w, C - h * 0.45)], fill=col)


def cube(d, col=INK):
    r = S * SS * 0.27
    pts = poly_regular(C, C, r, 6, rot=math.pi / 6)
    d.polygon(pts, outline=col, width=int(S * SS * 0.07))
    d.line([pts[1], (C, C)], fill=col, width=int(S * SS * 0.06))
    d.line([pts[3], (C, C)], fill=col, width=int(S * SS * 0.06))
    d.line([pts[5], (C, C)], fill=col, width=int(S * SS * 0.06))


def dragon(d, col=INK):
    # stylised "wing" wedge — used for the *arch-derived security distros
    d.polygon([(C, C - S * SS * 0.30), (C + S * SS * 0.30, C + S * SS * 0.26),
               (C, C + S * SS * 0.08), (C - S * SS * 0.30, C + S * SS * 0.26)], fill=col)


def window4(d, col=INK):
    g = S * SS * 0.028
    a = S * SS * 0.16
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x0 = C + dx * g - (a if dx < 0 else 0) + (g if dx > 0 else 0)
        y0 = C + dy * g - (a if dy < 0 else 0) + (g if dy > 0 else 0)
        d.rectangle([x0, y0, x0 + a, y0 + a], fill=col)


def circle_o(d, col=INK):
    r = S * SS * 0.25
    d.ellipse([C - r, C - r, C + r, C + r], outline=col, width=int(S * SS * 0.10))


def nix_flake(d, col=INK):
    r = S * SS * 0.28
    for ang in range(0, 360, 60):
        a = math.radians(ang)
        d.line([C, C, C + r * math.cos(a), C + r * math.sin(a)], fill=col, width=int(S * SS * 0.075))


def server_stack(d, col=INK):
    w, h, gap = S * SS * 0.46, S * SS * 0.115, S * SS * 0.055
    top = C - (h * 3 + gap * 2) / 2
    for i in range(3):
        y = top + i * (h + gap)
        d.rounded_rectangle([C - w / 2, y, C + w / 2, y + h], radius=h * 0.3, fill=col)


def penguin(d, col=INK):
    s = S * SS * 0.30
    d.ellipse([C - s * 0.72, C - s, C + s * 0.72, C + s], fill=col)
    d.ellipse([C - s * 0.44, C - s * 0.42, C + s * 0.44, C + s * 0.86], fill=(20, 34, 52, 255))
    d.polygon([(C - s * 0.16, C - s * 0.38), (C + s * 0.16, C - s * 0.38), (C, C - s * 0.10)],
              fill=(255, 183, 3, 255))


def cat_ears(d, col=INK):
    r = S * SS * 0.24
    d.ellipse([C - r, C - r * 0.7, C + r, C + r * 1.3], fill=col)
    d.polygon([(C - r * 0.95, C - r * 0.35), (C - r * 0.30, C - r * 0.75), (C - r * 0.42, C + r * 0.05)], fill=col)
    d.polygon([(C + r * 0.95, C - r * 0.35), (C + r * 0.30, C - r * 0.75), (C + r * 0.42, C + r * 0.05)], fill=col)


def pear(d, col=INK):
    d.ellipse([C - S * SS * 0.24, C - S * SS * 0.10, C + S * SS * 0.24, C + S * SS * 0.30], fill=col)
    d.ellipse([C - S * SS * 0.17, C - S * SS * 0.26, C + S * SS * 0.17, C + S * SS * 0.10], fill=col)
    d.line([C, C - S * SS * 0.24, C + S * SS * 0.10, C - S * SS * 0.34], fill=col, width=int(S * SS * 0.05))


def droid(d, col=INK):
    r = S * SS * 0.24
    d.pieslice([C - r, C - r * 1.1, C + r, C + r * 0.9], 180, 360, fill=col)
    d.rounded_rectangle([C - r, C - r * 0.05, C + r, C + r * 0.75], radius=r * 0.25, fill=col)
    for sx in (-1, 1):
        d.line([C + sx * r * 0.62, C - r * 1.10, C + sx * r * 0.95, C - r * 1.55], fill=col, width=int(S * SS * 0.05))


def tiny_dot(d, col=INK):
    r = S * SS * 0.13
    d.ellipse([C - r, C - r, C + r, C + r], fill=col)
    r2 = S * SS * 0.27
    d.ellipse([C - r2, C - r2, C + r2, C + r2], outline=col, width=int(S * SS * 0.05))


def chrome_o(d, col=INK):
    r = S * SS * 0.27
    d.ellipse([C - r, C - r, C + r, C + r], outline=col, width=int(S * SS * 0.09))
    rr = S * SS * 0.11
    d.ellipse([C - rr, C - rr, C + rr, C + rr], fill=col)


def vault_lock(d, col=INK):
    r = S * SS * 0.26
    d.ellipse([C - r, C - r, C + r, C + r], outline=col, width=int(S * SS * 0.07))
    for ang in range(0, 360, 45):
        a = math.radians(ang)
        d.line([C + r * 0.98 * math.cos(a), C + r * 0.98 * math.sin(a),
                C + r * 1.38 * math.cos(a), C + r * 1.38 * math.sin(a)],
               fill=col, width=int(S * SS * 0.06))


ICONS = {
    # class          background        glyph
    "arch":          ((23, 147, 209),  tri_up),
    "blackarch":     ((20, 24, 28),    dragon),
    "athena":        ((36, 44, 58),    dragon),
    "debian":        ((215, 10, 83),   swirl),
    "fedora":        ((41, 65, 114),   letter_f),
    "ubuntu":        ((233, 84, 32),   ring_dots),
    "mint":          ((105, 179, 100), leaf),
    "nixos":         ((82, 125, 190),  nix_flake),
    "popos":         ((72, 185, 199),  circle_o),
    "qubes":         ((58, 82, 164),   cube),
    "proxmox":       ((232, 119, 34),  server_stack),
    "void":          ((71, 143, 62),   circle_o),
    "kali":          ((33, 40, 51),    dragon),
    "windows":       ((0, 120, 212),   window4),
    "chromeos":      ((66, 133, 244),  chrome_o),
    "tinycore":      ((48, 62, 82),    tiny_dot),
    "android":       ((61, 220, 132),  droid),
    "anduinos":      ((0, 103, 184),   window4),
    "pearos":        ((150, 160, 170), pear),
    "nyarch":        ((203, 116, 190), cat_ears),
    "veloguard":     ((45, 106, 120),  shield),
    "security":      ((45, 106, 120),  shield),
    "linux":         ((38, 52, 70),    penguin),
    "vtoyret":       ((38, 52, 70),    circle_o),
    "unknown":       ((38, 52, 70),    penguin),
    "penguinvault":  ((13, 27, 42),    vault_lock),
}

for name, (bg, glyph) in ICONS.items():
    make(name, bg + (255,), glyph)

print(f"wrote {len(ICONS)} icons to {OUT}/ at {S}x{S}")
