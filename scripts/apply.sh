#!/usr/bin/env bash
# apply.sh — turn an existing Ventoy drive into a PenguinVault drive:
# install the theme, wire up per-distro menu icons, and (optionally) rename
# the volume label.
#
# Usage: ./apply.sh /path/to/ventoy-mountpoint [--label]
#   --label  also rename the filesystem label to PenguinVault. Needs root and
#            unmounts the drive, so it is opt-in rather than automatic.
#
# Idempotent: safe to re-run. Existing ventoy.json settings are merged, not
# replaced — your ISO list, persistence and auto-install rules are untouched.

set -euo pipefail

MP="${1:-}"
DO_LABEL="${2:-}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$HERE/theme/penguinvault"
LABEL="PenguinVault"

if [[ -z "$MP" || ! -d "$MP" ]]; then
	echo "Usage: $0 /path/to/ventoy-mountpoint [--label]" >&2
	exit 1
fi
if [[ ! -d "$MP/ventoy" ]] && [[ ! -d "$SRC" ]]; then
	echo "ERROR: $MP has no ventoy/ directory — is this a Ventoy drive?" >&2
	exit 1
fi
for c in python3 rsync; do
	command -v "$c" >/dev/null 2>&1 || { echo "ERROR: missing required command: $c" >&2; exit 1; }
done

# Refuse to install a theme we already know is broken.
if ! python3 "$HERE/scripts/validate_theme.py" "$SRC" >/dev/null; then
	echo "ERROR: theme failed validation — refusing to install it." >&2
	python3 "$HERE/scripts/validate_theme.py" "$SRC" >&2 || true
	exit 1
fi

DEST="$MP/ventoy/theme/penguinvault"
echo "==> Installing theme -> ventoy/theme/penguinvault"
mkdir -p "$DEST"
rsync -a --delete "$SRC"/ "$DEST"/
echo "    $(find "$DEST" -type f | wc -l) files"

echo "==> Merging ventoy.json"
python3 - "$MP" <<'PYEOF'
import json, os, sys

mp = sys.argv[1]
path = os.path.join(mp, "ventoy", "ventoy.json")
os.makedirs(os.path.dirname(path), exist_ok=True)

d = {}
if os.path.isfile(path) and os.path.getsize(path):
    try:
        d = json.load(open(path))
    except json.JSONDecodeError as e:
        # Never clobber a config we failed to understand.
        sys.exit(f"    ERROR: existing ventoy.json is not valid JSON ({e}). Fix or move it first.")

d["theme"] = {
    "file": "/ventoy/theme/penguinvault/theme.txt",
    "gfxmode": "max",
    "display_mode": "GUI",
    "ventoy_left": "6%",
    "ventoy_top": "95%",
    "ventoy_color": "#4f6a80",
    "fonts": [
        "/ventoy/theme/penguinvault/pv-title.pf2",
        "/ventoy/theme/penguinvault/pv-item.pf2",
        "/ventoy/theme/penguinvault/pv-small.pf2",
    ],
}

# Filename substring -> icon class (icons/<class>.png in the theme dir).
# Ventoy already classes the mainstream distros correctly on its own; these
# rules cover the ones it doesn't know about, and pin the rest so the icon
# set stays predictable.
rules = [
    ("blackarch",   "blackarch"), ("athenaos",  "athena"),   ("kali",      "kali"),
    ("archlinux",   "arch"),      ("debian",    "debian"),   ("fedora",    "fedora"),
    ("ubuntu",      "ubuntu"),    ("linuxmint", "mint"),     ("nixos",     "nixos"),
    ("pop-os",      "popos"),     ("qubes",     "qubes"),    ("proxmox",   "proxmox"),
    ("void-live",   "void"),      ("chromeos",  "chromeos"), ("tinycore",  "tinycore"),
    ("Win11",       "windows"),   ("windows",   "windows"),  ("AnduinOS",  "anduinos"),
    ("pearOS",      "pearos"),    ("Nyarch",    "nyarch"),   ("veloguard", "veloguard"),
    ("Bliss",       "android"),   ("ATV",       "android"),
]

existing = d.get("menu_class", [])
have = {(e.get("key"), e.get("dir"), e.get("parent")) for e in existing}
for key, cls in rules:
    if (key, None, None) not in have:
        existing.append({"key": key, "class": cls})
d["menu_class"] = existing

json.dump(d, open(path, "w"), indent=4)
print(f"    theme plugin set, {len(d['menu_class'])} menu_class rules")
PYEOF

if [[ "$DO_LABEL" == "--label" ]]; then
	echo "==> Renaming volume label to $LABEL"
	dev=$(findmnt -no SOURCE --target "$MP")
	echo "    device: $dev"
	if [[ $EUID -ne 0 ]]; then
		echo "    ERROR: --label needs root (relabelling requires the volume unmounted)." >&2
		echo "    Re-run as: sudo $0 $MP --label" >&2
		exit 1
	fi
	fstype=$(findmnt -no FSTYPE --target "$MP")
	sync
	umount "$MP"
	case "$fstype" in
		exfat) exfatlabel "$dev" "$LABEL" ;;
		vfat)  fatlabel   "$dev" "$LABEL" ;;
		ntfs)  ntfslabel --force "$dev" "$LABEL" ;;
		*) echo "    ERROR: don't know how to relabel $fstype" >&2; exit 1 ;;
	esac
	echo "    relabelled ($fstype)"
else
	echo "==> Skipping volume rename (pass --label as root to also rename it)"
fi

sync
echo
echo "PenguinVault applied."
