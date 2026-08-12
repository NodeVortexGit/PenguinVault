#!/usr/bin/env python3
"""Render an approximation of the PenguinVault boot menu.

Draws the same geometry theme.txt describes, using the real background and
the real icons, so you can see the result without rebooting. It is a mockup —
GRUB does the actual layout — but positions, colours and fonts are read from
the same values the theme uses.

Usage: make_preview.py THEME_DIR OUT.png [entries.txt]
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

THEME = sys.argv[1] if len(sys.argv) > 1 else "theme/penguinvault"
OUT = sys.argv[2] if len(sys.argv) > 2 else "docs/preview.png"

W, H = 1920, 1080
ICE = "#7fdfff"
SUB = "#6d8ba3"
ITEM = "#c9d6e2"
SEL = "#ffb703"
DIM = "#4f6a80"

FDIR = "/usr/share/fonts/dejavu-sans-fonts"
BOLD = os.path.join(FDIR, "DejaVuSans-Bold.ttf")
REG = os.path.join(FDIR, "DejaVuSans.ttf")


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


# Menu entries: (label, icon class). Mirrors a real drive's contents.
ENTRIES = [
    ("archlinux-2026.08.01-x86_64.iso", "arch"),
    ("debian-13.6.0-amd64-netinst.iso", "debian"),
    ("Fedora-Workstation-Live-44-1.7.x86_64.iso", "fedora"),
    ("ubuntu-26.04-desktop-amd64.iso", "ubuntu"),
    ("linuxmint-22.3-cinnamon-64bit.iso", "mint"),
    ("kali-linux-2026.2-installer-amd64.iso", "kali"),
    ("blackarch-linux-full-2023.04.01-x86_64.iso", "blackarch"),
    ("Qubes-R4.3.1-x86_64.iso", "qubes"),
    ("nixos-graphical-26.05-x86_64-linux.iso", "nixos"),
    ("proxmox-ve_9.2-1.iso", "proxmox"),
    ("Win11_25H2_English_x64_v2.iso", "windows"),
]
SELECTED = 5

if len(sys.argv) > 3 and os.path.isfile(sys.argv[3]):
    ENTRIES = []
    for line in open(sys.argv[3]):
        line = line.strip()
        if line:
            name, _, cls = line.partition("|")
            ENTRIES.append((name, cls or "unknown"))

bg = os.path.join(THEME, "background.png")
img = Image.open(bg).convert("RGB").resize((W, H), Image.LANCZOS) if os.path.isfile(bg) \
    else Image.new("RGB", (W, H), (10, 20, 34))
d = ImageDraw.Draw(img)

# Wordmark (theme.txt: left 6%, top 7% / 15%)
d.text((W * 0.06, H * 0.07), "PenguinVault", font=font(BOLD, 32), fill=ICE)
d.text((W * 0.06, H * 0.15), "multiboot rescue + install vault", font=font(REG, 16), fill=SUB)

# Boot menu (left 6%, top 23%, width 58%, item_height 38, spacing 8, icon 32)
left, top = W * 0.06, H * 0.23
item_h, spacing, icon_sz, icon_gap = 38, 8, 32, 18
f_item = font(REG, 20)

for i, (label, cls) in enumerate(ENTRIES):
    y = top + i * (item_h + spacing)
    selected = i == SELECTED
    if selected:
        d.rounded_rectangle([left - 10, y - 4, left + W * 0.58, y + item_h + 2],
                            radius=6, fill=(20, 40, 62))
    ipath = os.path.join(THEME, "icons", f"{cls}.png")
    if os.path.isfile(ipath):
        ic = Image.open(ipath).convert("RGBA").resize((icon_sz, icon_sz), Image.LANCZOS)
        img.paste(ic, (int(left), int(y + (item_h - icon_sz) / 2)), ic)
    d.text((left + icon_sz + icon_gap, y + item_h / 2), label,
           font=f_item, fill=SEL if selected else ITEM, anchor="lm")

# Countdown bar (top 85%, height 14)
by = H * 0.85
d.rectangle([W * 0.06, by, W * 0.06 + W * 0.58, by + 14], fill=(18, 38, 58))
d.rectangle([W * 0.06, by, W * 0.06 + W * 0.58 * 0.62, by + 14], fill="#48cae4")
d.text((W * 0.06, by + 26), "Booting in 12s", font=font(REG, 16), fill=SUB)

# Hotkey hints (top 92%)
d.text((W * 0.06, H * 0.92),
       "F1 memdisk   F2 power   F3 tree   F4 local disk   F5 tools   F6 submenu   Ctrl+w quit",
       font=font(REG, 16), fill=DIM)

os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
img.save(OUT, "PNG", optimize=True)
print(f"wrote {OUT}")
