#!/usr/bin/env python3
"""Sanity-check a GRUB2 theme before it goes near a boot drive.

GRUB fails quietly: a bad colour or a missing font leaves you staring at a
half-drawn menu with no error to read. This catches the things that actually
break — malformed colours, unbalanced braces, references to files that aren't
there, and font names that don't match what's registered inside the .pf2s.

Usage: validate_theme.py THEME_DIR
Exit 0 = clean, 1 = problems found.
"""
import os
import re
import struct
import sys

d = sys.argv[1] if len(sys.argv) > 1 else "."
theme = os.path.join(d, "theme.txt")
errors, warnings = [], []

if not os.path.isfile(theme):
    print(f"FAIL: no theme.txt in {d}")
    sys.exit(1)

text = open(theme, encoding="utf-8").read()
lines = text.split("\n")

# ── fonts registered inside the shipped .pf2 files ──────────────────────────
registered = set()
for f in sorted(os.listdir(d)):
    if not f.endswith(".pf2"):
        continue
    data = open(os.path.join(d, f), "rb").read()
    i = data.find(b"NAME")
    if i < 0:
        warnings.append(f"{f}: no NAME section")
        continue
    ln = struct.unpack(">I", data[i + 4:i + 8])[0]
    registered.add(data[i + 8:i + 8 + ln].rstrip(b"\0").decode("utf-8", "replace"))

def strip_comment(line):
    """Drop a trailing # comment without eating '#rrggbb' inside quotes."""
    out, in_str = [], False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == "#" and not in_str:
            break
        out.append(ch)
    return "".join(out)


# ── brace balance ───────────────────────────────────────────────────────────
depth = 0
for n, line in enumerate(lines, 1):
    code = strip_comment(line)
    depth += code.count("{") - code.count("}")
    if depth < 0:
        errors.append(f"line {n}: unbalanced '}}'")
        break
if depth > 0:
    errors.append(f"{depth} unclosed '{{' at end of file")

# ── colours ─────────────────────────────────────────────────────────────────
for n, line in enumerate(lines, 1):
    for m in re.finditer(r'(\w[\w-]*)\s*[:=]\s*"(#[^"]*)"', line):
        key, val = m.group(1), m.group(2)
        if not re.fullmatch(r"#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}", val):
            errors.append(f'line {n}: {key} has malformed colour "{val}"')

# ── font references ─────────────────────────────────────────────────────────
for n, line in enumerate(lines, 1):
    for m in re.finditer(r'(\w[\w-]*font\w*)\s*[:=]\s*"([^"]+)"', line, re.I):
        key, val = m.group(1), m.group(2)
        if not val:
            continue
        if registered and val not in registered:
            errors.append(f'line {n}: {key} = "{val}" is not a font this theme ships '
                          f'(have: {", ".join(sorted(registered))})')

# ── referenced image files ──────────────────────────────────────────────────
for n, line in enumerate(lines, 1):
    for m in re.finditer(r'[:=]\s*"([^"]*\.png)"', line):
        ref = m.group(1)
        if "*" in ref:
            base = ref.replace("*", "")
            stem = os.path.splitext(base)[0]
            if not any(f.startswith(stem.rstrip("_")) for f in os.listdir(d)):
                errors.append(f'line {n}: pixmap style "{ref}" has no matching files')
        elif not os.path.isfile(os.path.join(d, ref)):
            errors.append(f'line {n}: missing image "{ref}"')

# ── icons ───────────────────────────────────────────────────────────────────
icondir = os.path.join(d, "icons")
if os.path.isdir(icondir):
    icons = [f for f in os.listdir(icondir) if f.endswith(".png")]
    if not icons:
        warnings.append("icons/ exists but contains no .png files")
else:
    warnings.append("no icons/ directory — menu entries will render without icons")

# ── report ──────────────────────────────────────────────────────────────────
for w in warnings:
    print(f"WARN: {w}")
for e in errors:
    print(f"FAIL: {e}")
if not errors:
    n_icons = len(os.listdir(icondir)) if os.path.isdir(icondir) else 0
    print(f"OK: theme.txt valid — {len(registered)} font(s), {n_icons} icon(s)")
sys.exit(1 if errors else 0)
