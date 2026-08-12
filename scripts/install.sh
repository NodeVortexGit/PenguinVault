#!/usr/bin/env bash
# install.sh — build a PenguinVault drive from scratch: fetch the latest
# Ventoy release, install it to the target disk with the PenguinVault label,
# then apply the theme and icons.
#
# Usage: sudo ./install.sh /dev/sdX [--gpt] [--secure-boot]
#
# THIS ERASES THE TARGET DISK. It refuses to touch anything that isn't
# removable unless you type the confirmation phrase.
#
# Already have a Ventoy drive you want to convert? Don't use this — run
# scripts/apply.sh against its mountpoint instead and keep your ISOs.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LABEL="PenguinVault"
DEV="${1:-}"
shift || true
PART_STYLE=""
SECURE=""
for arg in "$@"; do
	case "$arg" in
		--gpt)         PART_STYLE="-g" ;;
		--secure-boot) SECURE="-s" ;;
		*) echo "Unknown option: $arg" >&2; exit 1 ;;
	esac
done

if [[ -z "$DEV" ]]; then
	echo "Usage: sudo $0 /dev/sdX [--gpt] [--secure-boot]" >&2
	echo
	echo "Removable disks currently attached:" >&2
	lsblk -dno NAME,SIZE,TRAN,MODEL | awk '$3=="usb"{print "  /dev/"$0}' >&2
	exit 1
fi
if [[ $EUID -ne 0 ]]; then
	echo "ERROR: must run as root (Ventoy writes the partition table)." >&2
	exit 1
fi
if [[ ! -b "$DEV" ]]; then
	echo "ERROR: $DEV is not a block device." >&2
	exit 1
fi
for c in curl tar lsblk python3 rsync; do
	command -v "$c" >/dev/null 2>&1 || { echo "ERROR: missing required command: $c" >&2; exit 1; }
done

# Validate the theme before wiping anything — no point erasing a disk and
# then discovering the payload is broken.
if ! python3 "$HERE/scripts/validate_theme.py" "$HERE/theme/penguinvault" >/dev/null; then
	echo "ERROR: theme failed validation; aborting before touching $DEV." >&2
	python3 "$HERE/scripts/validate_theme.py" "$HERE/theme/penguinvault" >&2 || true
	exit 1
fi

TRAN=$(lsblk -dno TRAN "$DEV" | head -1)
SIZE=$(lsblk -dno SIZE "$DEV" | head -1)
MODEL=$(lsblk -dno MODEL "$DEV" | head -1 | xargs || true)
echo "Target: $DEV  ($SIZE, ${TRAN:-unknown}, ${MODEL:-unknown})"
echo
lsblk "$DEV"
echo
echo "!!! EVERYTHING ON $DEV WILL BE DESTROYED !!!"
if [[ "$TRAN" != "usb" ]]; then
	echo "!!! AND $DEV IS NOT A USB DEVICE — this looks like an internal disk. !!!"
fi
read -r -p "Type ERASE to continue: " confirm </dev/tty
[[ "$confirm" == "ERASE" ]] || { echo "Cancelled."; exit 0; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo
echo "==> Fetching the latest Ventoy release"
VER=$(curl -fsSL https://api.github.com/repos/ventoy/Ventoy/releases/latest \
      | grep -oE '"tag_name" *: *"[^"]+"' | head -1 | cut -d'"' -f4 | tr -d 'v' || true)
if [[ -z "$VER" ]]; then
	echo "ERROR: couldn't determine the latest Ventoy version (network or API rate limit)." >&2
	exit 1
fi
URL="https://github.com/ventoy/Ventoy/releases/download/v${VER}/ventoy-${VER}-linux.tar.gz"
echo "    v$VER"
if ! curl -fsSL -o "$WORK/ventoy.tar.gz" "$URL"; then
	echo "ERROR: download failed: $URL" >&2
	exit 1
fi
tar -xzf "$WORK/ventoy.tar.gz" -C "$WORK"
VDIR=$(find "$WORK" -maxdepth 1 -type d -name 'ventoy-*' | head -1)
[[ -x "$VDIR/Ventoy2Disk.sh" ]] || { echo "ERROR: Ventoy2Disk.sh missing from the archive" >&2; exit 1; }

echo
echo "==> Installing Ventoy to $DEV with label '$LABEL'"
# -L is Ventoy's documented option for the main partition's label.
sh "$VDIR/Ventoy2Disk.sh" -i $PART_STYLE $SECURE -L "$LABEL" "$DEV"

echo
echo "==> Waiting for the new partition to appear"
udevadm settle 2>/dev/null || true
PART=""
for _ in $(seq 1 15); do
	cand=$(lsblk -lno NAME,LABEL "$DEV" | awk -v l="$LABEL" '$2==l{print $1; exit}')
	if [[ -n "$cand" ]]; then PART="/dev/$cand"; break; fi
	sleep 1
done
[[ -n "$PART" ]] || { echo "ERROR: couldn't find the '$LABEL' partition after install." >&2; exit 1; }
echo "    $PART"

MNT="$WORK/mnt"
mkdir -p "$MNT"
mount "$PART" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true; rm -rf "$WORK"' EXIT

echo
"$HERE/scripts/apply.sh" "$MNT"

sync
umount "$MNT"
trap 'rm -rf "$WORK"' EXIT

echo
echo "PenguinVault is ready on $DEV."
echo "Drop ISOs anywhere on the drive and they'll show up in the boot menu."
