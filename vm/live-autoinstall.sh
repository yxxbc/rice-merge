#!/usr/bin/env bash
# Runs INSIDE the Arch live ISO (VM): mount the 9p share, pick the target disk,
# write an unattended config, and run live/install.sh.
#
#   bash /repo/vm/live-autoinstall.sh smoke   # fast: dotfiles + 04n only, NO desktop
#   bash /repo/vm/live-autoinstall.sh full    # real install, reaches niri desktop (slow on TCG)
#
# Override the disk with DISK=/dev/vdb. Set REBOOT=0 to stay in the live shell.

set -uo pipefail

PROFILE="${1:-full}"
REBOOT="${REBOOT:-1}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root in the live ISO." >&2; exit 1; }
[[ -d /run/archiso ]] || { echo "Not an Arch live environment." >&2; exit 1; }
case "$PROFILE" in smoke|full) ;; *) echo "Usage: $0 [smoke|full]" >&2; exit 2 ;; esac

# Live console default font is tiny; double it, then prefer a 16x32 Terminus if present.
if command -v setfont >/dev/null 2>&1; then
    setfont -d 2>/dev/null || true
    for f in ter-132n ter-128n; do
        if [[ -f "/usr/share/kbd/consolefonts/$f.psfu.gz" ]]; then
            setfont "$f" 2>/dev/null && break
        fi
    done
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- mount the host share -------------------------------------------------------
if [[ ! -f "$REPO/live/install.sh" ]]; then
    echo "==> Mounting 9p share at $REPO"
    modprobe 9pnet_virtio 2>/dev/null || true
    mkdir -p "$REPO"
    mount -t 9p -o trans=virtio,version=9p2000.L repo "$REPO" || {
        echo "9p mount failed. If you moved this script, mount manually:" >&2
        echo "  mkdir -p /repo && mount -t 9p -o trans=virtio,version=9p2000.L repo /repo" >&2
        exit 1
    }
fi
[[ -f "$REPO/live/install.sh" ]] || { echo "Repository not found at $REPO" >&2; exit 1; }

# --- pick the target disk -------------------------------------------------------
if [[ -z "${DISK:-}" ]]; then
    live_src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
    live_parent=""
    if [[ -n "$live_src" ]]; then
        live_parent="$(lsblk -no PKNAME "$live_src" 2>/dev/null | head -1)"
    fi

    candidates=()
    while IFS= read -r dev; do
        [[ -z "$dev" ]] && continue
        name="$(basename "$dev")"
        [[ -n "$live_parent" && "$name" == "$live_parent" ]] && continue
        size="$(lsblk -bndo SIZE "$dev" 2>/dev/null | head -1)"
        [[ -n "$size" ]] || continue
        (( size >= 20 * 1024 * 1024 * 1024 )) || continue
        candidates+=("$dev")
    done < <(lsblk -d -e 7,11 -npo NAME)

    case "${#candidates[@]}" in
        0) echo "No target disk found (VM disk attached? >= 20GiB?)" >&2; exit 1 ;;
        1) DISK="${candidates[0]}" ;;
        *)
            echo "More than one candidate disk:" >&2
            printf '  %s\n' "${candidates[@]}" >&2
            echo "Pick one: DISK=/dev/xxx bash $0 $PROFILE" >&2
            exit 1
            ;;
    esac
fi

echo "==> Target disk : $DISK"
echo "==> Profile     : $PROFILE"
if [[ "$PROFILE" == "smoke" ]]; then
    echo "    smoke skips package installation: it validates the merge only, no desktop."
else
    echo "    full installs packages + AUR; on emulated x86_64 this can take hours."
fi

cat >/tmp/rice-auto.env <<EOF
DISK=$DISK
ALLOW_WIPE=yes
SYS_HOSTNAME=arch
USERNAME=arch
USER_PASSWORD=arch
ROOT_PASSWORD=arch
TIMEZONE=Asia/Shanghai
LOCALE=zh_CN.UTF-8
KEYMAP=us
PROFILE=$PROFILE
SWAP=zram
GRUB_REMOVABLE=1
SKIP_NET_CHECK=0
REBOOT=$REBOOT
EOF

echo ""
echo "==> Config: /tmp/rice-auto.env"
echo "    (Ctrl+C now if the disk is wrong; starting in 5s)"
for i in 5 4 3 2 1; do
    printf '\r    %s...' "$i"
    sleep 1
done
echo ""

exec bash "$REPO/live/install.sh" --config /tmp/rice-auto.env --yes
