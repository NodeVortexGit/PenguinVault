#!/usr/bin/env bash
# convert-to-ntfs.sh — reformat a Ventoy data partition from exFAT to NTFS,
# so the volume can carry the full 12-character "PenguinVault" label that
# exFAT's 11-character limit forbids.
#
# Usage: sudo ./convert-to-ntfs.sh /dev/sdX1 [staging-dir]
#   staging-dir defaults to ~/.penguinvault-migration
#
# THIS REFORMATS THE PARTITION. Everything on it is copied to the staging
# directory first, checksummed, restored afterwards, and checksummed again.
# The staging copy is never deleted automatically — you remove it once you're
# satisfied, which means a failure at any point still leaves a full copy.
#
# Ventoy itself is unaffected: its bootloader lives in the MBR and on the
# VTOYEFI partition, neither of which is touched, and NTFS is one of the
# filesystems Ventoy supports for the data partition.

set -euo pipefail

DEV="${1:-}"
STAGE="${2:-$HOME/.penguinvault-migration}"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LABEL="PenguinVault"

if [[ -z "$DEV" || ! -b "$DEV" ]]; then
	echo "Usage: sudo $0 /dev/sdX1 [staging-dir]" >&2
	exit 1
fi
if [[ $EUID -ne 0 ]]; then
	echo "ERROR: must run as root (mkfs)." >&2
	exit 1
fi
for c in rsync mkfs.ntfs sha256sum findmnt lsblk; do
	command -v "$c" >/dev/null 2>&1 || { echo "ERROR: missing $c" >&2; exit 1; }
done

MP=$(findmnt -no TARGET "$DEV" || true)
[[ -n "$MP" ]] || { echo "ERROR: $DEV is not mounted; mount it first." >&2; exit 1; }

fstype=$(findmnt -no FSTYPE "$DEV")
used=$(df --output=used -B1 "$MP" | tail -1 | tr -dc '0-9')
mkdir -p "$STAGE"
avail=$(df --output=avail -B1 "$STAGE" | tail -1 | tr -dc '0-9')

echo "Device:   $DEV ($fstype, $(numfmt --to=iec "$used" 2>/dev/null || echo "$used bytes") used)"
echo "Mount:    $MP"
echo "Staging:  $STAGE ($(numfmt --to=iec "$avail" 2>/dev/null || echo "$avail bytes") free)"
echo
if (( avail < used + 1024*1024*1024 )); then
	echo "ERROR: not enough room in $STAGE to hold the drive's contents." >&2
	exit 1
fi
echo "!!! $DEV WILL BE REFORMATTED AS NTFS !!!"
read -r -p "Type CONVERT to continue: " confirm </dev/tty
[[ "$confirm" == "CONVERT" ]] || { echo "Cancelled."; exit 0; }

echo
echo "==> 1/6 Copying $MP -> $STAGE"
rsync -a --info=progress2 --no-inc-recursive \
	--exclude 'System Volume Information' --exclude '*.part' --exclude '.Trash-*' \
	"$MP"/ "$STAGE"/

echo
echo "==> 2/6 Checksumming the staged copy"
( cd "$STAGE" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) > "$STAGE.sha256"
echo "    $(wc -l < "$STAGE.sha256") files"

echo
echo "==> 3/6 Reformatting $DEV as NTFS, label '$LABEL'"
sync
umount "$MP"
mkfs.ntfs -Q -L "$LABEL" "$DEV"

echo
echo "==> 4/6 Remounting and restoring"
NEWMP=$(mktemp -d)
mount -t ntfs3 "$DEV" "$NEWMP" 2>/dev/null || mount "$DEV" "$NEWMP"
rsync -a --info=progress2 --no-inc-recursive "$STAGE"/ "$NEWMP"/

echo
echo "==> 5/6 Verifying the restored copy"
sync
if ( cd "$NEWMP" && sha256sum -c --quiet "$STAGE.sha256" ); then
	echo "    all files match"
else
	echo "    ERROR: checksum mismatch after restore." >&2
	echo "    Your data is still intact in $STAGE — do not delete it." >&2
	exit 1
fi

echo
echo "==> 6/6 Reapplying the PenguinVault theme"
"$HERE/scripts/apply.sh" "$NEWMP"

sync
umount "$NEWMP"
rmdir "$NEWMP"

echo
echo "Done. $DEV is now NTFS, labelled '$LABEL'."
echo "The staging copy is still at $STAGE — delete it once you've booted the"
echo "drive and confirmed everything works:"
echo "    rm -rf $STAGE $STAGE.sha256"
