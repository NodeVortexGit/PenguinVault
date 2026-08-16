#!/usr/bin/env bash
# update-isos.sh — audit the ISOs on a PenguinVault/Ventoy drive against the
# current upstream releases, and optionally download the ones that lag.
#
# Usage:
#   ./update-isos.sh /path/to/drive            # audit only (default, read-only)
#   ./update-isos.sh /path/to/drive --update   # also download what's outdated
#
# The manifest below is a point-in-time snapshot (see MANIFEST_DATE). Rolling
# distros and undated community spins can't be checked mechanically from a
# filename, so they're reported as "unknown — check manually" rather than
# guessed at. Nothing is ever deleted: a replacement is downloaded to
# "<name>.part", verified if a checksum is known, moved into place with an
# atomic rename, and only then is the superseded file removed.

set -euo pipefail

MANIFEST_DATE="2026-08-12"

MP="${1:-}"
MODE="${2:-audit}"
if [[ -z "$MP" || ! -d "$MP" ]]; then
	echo "Usage: $0 /path/to/drive [--update]" >&2
	exit 1
fi
for c in find awk sed; do
	command -v "$c" >/dev/null 2>&1 || { echo "ERROR: missing $c" >&2; exit 1; }
done
if [[ "$MODE" == "--update" ]] && ! command -v wget >/dev/null 2>&1; then
	echo "ERROR: --update needs wget" >&2; exit 1
fi

# match | current version | url (empty = no automatic download) | note | version regex
#
# The 5th field is an optional ERE with one capture group, used to pull the
# version out of the filename. It exists because generic heuristics get this
# wrong in both directions: "Fedora-...-Live-44-1.7" would yield 1.7, and
# "nixos-graphical-26.05.7376.fcb8fcd" would yield 26.05.7376. When it's
# empty the generic fallback below is used.
read -r -d '' MANIFEST <<'EOF' || true
archlinux-|2026.08.01|https://geo.mirror.pkgbuild.com/iso/2026.08.01/archlinux-2026.08.01-x86_64.iso|monthly snapshot|
debian-|13.6.0|https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso|stable point release|
Fedora-Workstation|44|https://download.fedoraproject.org/pub/fedora/linux/releases/44/Workstation/x86_64/iso/|next is 45, ~Oct 2026|Live-([0-9]+)
ubuntu-|26.04|https://releases.ubuntu.com/26.04/|26.04.1 slipped to ~27 Aug 2026|
linuxmint-|22.3|https://linuxmint.com/download.php|22.3 Zena; Mint 23 due Christmas 2026|
nixos-|26.05|https://channels.nixos.org/nixos-26.05/latest-nixos-graphical-x86_64-linux.iso|Yarara, May 2026|nixos-[a-z]+-([0-9]+\.[0-9]+)
pop-os_|24.04|https://system76.com/pop/download|COSMIC Epoch 1, Dec 2025|
Qubes-|R4.3.1|https://www.qubes-os.org/downloads/|June 2026|
proxmox-ve_|9.2|https://www.proxmox.com/en/downloads|May 2026|
OPNsense-|26.7|https://opnsense.c0urier.net/releases/26.7/OPNsense-26.7-dvd-amd64.iso.bz2|use the dvd ISO, not the vga .img|OPNsense-([0-9]+\.[0-9]+)-
void-live-|20250202|https://repo-default.voidlinux.org/live/current/|newest live image upstream ships|
blackarch-linux-full-|2023.04.01|https://blackarch.org/downloads.html|upstream has cut no newer full ISO|
kali-linux-|2026.2|https://cdimage.kali.org/kali-2026.2/kali-linux-2026.2-installer-amd64.iso|quarterly|
AnduinOS-|2.0.1|https://www.anduinos.com/|2.x is torrent/website-only, no direct ISO to fetch|
TinyCore|17.1|http://www.tinycorelinux.net/17.x/x86/release/|CorePlus edition; filename carries no version|
Win11_|25H2|https://www.microsoft.com/software-download/windows11|26H2 not public yet|
cachyos-|260809|https://mirror.cachyos.org/ISO/desktop/260809/cachyos-desktop-linux-260809.iso|rolling Arch base, dated snapshots|cachyos-desktop-linux-([0-9]{6})
PikaOS-|26.04.04|https://iso.pika-os.com/PikaOS-Nest-KDE-4.0-amd64-v3-26.04.04-1.iso|Nest 4.0, KDE, non-NVIDIA|v3-([0-9]+\.[0-9]+\.[0-9]+)
bazzite-|stable|https://download.bazzite.gg/bazzite-stable-amd64.iso|rolling "stable" tag, AMD/Intel image|(stable)
chromeos_|rolling|https://cros.tech/|reven builds roll continuously|
athenaos-|rolling||rolling release, filename carries no version|
pearOS-|unknown||community spin, no published version feed|
Nyarch-|unknown||community spin, no published version feed|
veloguardos-|unknown||community spin, no published version feed|
Bliss-|unknown||Android x86 spin|
ATV|unknown||Android TV x86 spin|
EOF

# Pull a version-ish token out of an ISO filename.
extract_ver() {
	local f="$1" re="${2:-}"
	if [[ -n "$re" ]]; then
		[[ "$f" =~ $re ]] && echo "${BASH_REMATCH[1]}" || echo ""
		return
	fi
	if [[ "$f" =~ ([0-9]{4}\.[0-9]{2}\.[0-9]{2}) ]]; then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ ([0-9]{4}\.[0-9]) ]];               then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ [-_]([0-9]{8})[-_.] ]];             then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ [Rr]([0-9]+\.[0-9]+\.[0-9]+) ]];    then echo "R${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]];        then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ ([0-9]+\.[0-9]+-[0-9]+) ]];         then echo "${BASH_REMATCH[1]%-*}"; return; fi
	if [[ "$f" =~ ([0-9]+\.[0-9]+) ]];                then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ (2[0-9]H[12]) ]];                   then echo "${BASH_REMATCH[1]}"; return; fi
	if [[ "$f" =~ -([0-9]+)- ]];                      then echo "${BASH_REMATCH[1]}"; return; fi
	echo ""
}

printf '%s\n' "PenguinVault ISO audit  (manifest snapshot: $MANIFEST_DATE)"
printf '%s\n' "-------------------------------------------------------------------------"

cur=0; old=0; unk=0
declare -a OUTDATED=()

while IFS= read -r iso; do
	base=$(basename "$iso")
	matched=""; want=""; url=""; note=""; vre=""
	while IFS='|' read -r m v u n r; do
		[[ -z "$m" ]] && continue
		if [[ "$base" == *"$m"* ]]; then matched="$m"; want="$v"; url="$u"; note="$n"; vre="$r"; break; fi
	done <<< "$MANIFEST"

	have=$(extract_ver "$base" "$vre")

	if [[ -z "$matched" ]]; then
		printf '  ?  %-58s (not in manifest)\n' "${base:0:58}"
		unk=$((unk+1))
	elif [[ "$want" == "rolling" || "$want" == "unknown" ]]; then
		printf '  ?  %-58s %s\n' "${base:0:58}" "$note"
		unk=$((unk+1))
	elif [[ -z "$have" ]]; then
		# No version in the filename: say so instead of calling it outdated.
		printf '  ?  %-58s no version in filename; upstream is %s\n' "${base:0:58}" "$want"
		[[ -n "$note" ]] && printf '     %s\n' "$note"
		unk=$((unk+1))
	elif [[ "$have" == "$want" ]]; then
		printf '  OK %-58s %s\n' "${base:0:58}" "$want"
		cur=$((cur+1))
	else
		printf '  !! %-58s have %s -> current %s\n' "${base:0:58}" "${have:-?}" "$want"
		[[ -n "$note" ]] && printf '     %s\n' "$note"
		[[ -n "$url"  ]] && printf '     %s\n' "$url"
		old=$((old+1))
		OUTDATED+=("$iso|$want|$url")
	fi
done < <(find "$MP" -iname '*.iso' -type f | sort)

printf '%s\n' "-------------------------------------------------------------------------"
printf '  %d current, %d outdated, %d unverifiable\n\n' "$cur" "$old" "$unk"

if [[ "$MODE" != "--update" ]]; then
	(( old > 0 )) && echo "Re-run with --update to download the outdated ones."
	exit 0
fi
if (( old == 0 )); then
	echo "Nothing to update."
	exit 0
fi

for entry in "${OUTDATED[@]}"; do
	IFS='|' read -r iso want url <<< "$entry"
	base=$(basename "$iso")
	dir=$(dirname "$iso")
	if [[ -z "$url" || "$url" != *.iso ]]; then
		echo "SKIP $base — no direct ISO URL in the manifest; grab it manually:"
		echo "     ${url:-<no url>}"
		continue
	fi
	new="$dir/$(basename "$url")"
	part="$new.part"
	echo "==> $base -> $(basename "$url")"
	if [[ -f "$new" ]]; then
		echo "    already present, skipping download"
	else
		# Grab the project's own SHA256SUMS next to the ISO when it publishes
		# one, so a corrupted or truncated download can't replace a good ISO.
		want_sum=""
		sums_url="${url%/*}/SHA256SUMS"
		want_sum=$(curl -fsSL --max-time 30 "$sums_url" 2>/dev/null \
			| awk -v f="$(basename "$url")" '$2==f || $2=="*"f {print $1; exit}') || true

		if ! wget -q --show-progress --tries=3 --timeout=60 -O "$part" -- "$url" </dev/null; then
			echo "    ERROR: download failed" >&2
			rm -f -- "$part"
			continue
		fi
		if [[ -n "$want_sum" ]]; then
			got=$(sha256sum "$part" | awk '{print $1}')
			if [[ "$got" != "$want_sum" ]]; then
				echo "    ERROR: checksum mismatch — keeping the old ISO" >&2
				echo "      want $want_sum" >&2
				echo "      got  $got" >&2
				rm -f -- "$part"
				continue
			fi
			echo "    checksum verified"
		else
			echo "    (upstream publishes no SHA256SUMS next to the ISO)"
		fi
		mv -f -- "$part" "$new"
		echo "    downloaded"
	fi
	# Only now remove the superseded image, and only if it isn't the new one.
	if [[ "$iso" != "$new" && -f "$new" ]]; then
		rm -f -- "$iso"
		echo "    removed old $base"
	fi
done

sync
echo
echo "Done. Re-run without --update to confirm."
