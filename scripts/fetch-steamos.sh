#!/usr/bin/env bash
# fetch-steamos.sh — put Valve's SteamOS image on a Ventoy drive.
#
# Usage: ./fetch-steamos.sh /path/to/drive/target-folder
#
# Why this needs its own script rather than a line in update-isos.sh:
#
#   * Valve doesn't publish a SteamOS ISO. The download on
#     store.steampowered.com/steamos/download/ is a raw disk image,
#     steamdeck-repair-latest.img.bz2, intended to be flashed with Rufus or
#     Etcher. Since SteamOS 3.8 (June 2026) that same image also installs on
#     generic PCs — with an AMD GPU; NVIDIA support is slated for 2027.
#   * It arrives bzip2-compressed and Ventoy cannot boot a .bz2, so it has to
#     be expanded to a raw .img first. Ventoy does support .img.
#   * The compressed file gives no hint of its expanded size, so this streams
#     the download straight through the decompressor (never storing the 3 GB
#     archive) and watches free space, aborting cleanly rather than filling
#     the drive.
#
# Valve publishes no checksum for this image, so there is nothing to verify
# it against — unlike every other download in this repo.

set -euo pipefail

DEST_DIR="${1:-}"
URL="https://steamdeck-images.steamos.cloud/recovery/steamdeck-repair-latest.img.bz2"
NAME="SteamOS.img"
MIN_FREE=$(( 1500 * 1024 * 1024 ))   # abort if free space drops below 1.5 GB

if [[ -z "$DEST_DIR" || ! -d "$DEST_DIR" ]]; then
	echo "Usage: $0 /path/to/drive/target-folder" >&2
	exit 1
fi
for c in curl bunzip2 df awk; do
	command -v "$c" >/dev/null 2>&1 || { echo "ERROR: missing $c" >&2; exit 1; }
done

out="$DEST_DIR/$NAME"
part="$out.part"

if [[ -f "$out" ]]; then
	echo "$NAME already present ($(du -h "$out" | cut -f1)) — nothing to do."
	exit 0
fi

echo "==> Streaming $URL"
echo "    -> $out (decompressing on the fly)"
rm -f -- "$part"

set +e
curl -fsSL --max-time 7200 "$URL" | bunzip2 -c > "$part" &
pipe_pid=$!

# Watchdog: kill the transfer if the drive is about to fill up.
aborted=0
while kill -0 "$pipe_pid" 2>/dev/null; do
	free=$(df --output=avail -B1 "$DEST_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
	if [[ -n "$free" ]] && (( free < MIN_FREE )); then
		echo "    ERROR: free space fell below $(( MIN_FREE / 1024 / 1024 )) MB — aborting." >&2
		pkill -P "$pipe_pid" 2>/dev/null
		kill "$pipe_pid" 2>/dev/null
		aborted=1
		break
	fi
	sleep 5
done
wait "$pipe_pid"
rc=$?
set -e

if (( aborted )) || (( rc != 0 )); then
	echo "    failed (exit $rc); removing partial file" >&2
	rm -f -- "$part"
	exit 1
fi

# A truncated stream still exits 0 in some curl/bunzip2 combinations, so
# sanity-check that we got a plausible disk image rather than a stub.
size=$(stat -c%s "$part")
if (( size < 1024 * 1024 * 1024 )); then
	echo "    ERROR: expanded image is only $(( size / 1024 / 1024 )) MB — looks truncated." >&2
	rm -f -- "$part"
	exit 1
fi
# Raw disk images start with an MBR/protective-MBR ending in 0x55AA.
sig=$(dd if="$part" bs=1 skip=510 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [[ "$sig" != "55aa" ]]; then
	echo "    WARNING: no 0x55AA boot signature at offset 510 (got '${sig:-none}')." >&2
	echo "             The file may still be usable, but it doesn't look like a" >&2
	echo "             bootable disk image." >&2
fi

mv -f -- "$part" "$out"
sync
echo "    done: $(du -h "$out" | cut -f1)"
echo
echo "Note: Ventoy boots .img files, but this image is built for Steam Deck"
echo "hardware and generic-PC SteamOS needs an AMD GPU. If it doesn't boot"
echo "from the menu, flash it to its own stick with Rufus/Etcher instead."
