#!/usr/bin/env bash
# Arch live ISO installer: partition -> pacstrap -> chroot base -> deploy -> modules
#
# Run inside the Arch live ISO as root:
#   bash live/install.sh --list-disks
#   bash live/install.sh --config live/install.env --dry-run
#   bash live/install.sh --config live/install.env
#
# Options:
#   --config FILE     config file (see live/install.env.example)
#   --dry-run         print commands instead of running them
#   --from STEP       start at: partition|bootstrap|chroot|deploy|modules
#   --yes             skip the "type the disk path" confirmation
#   --list-disks      list candidate disks and exit
#
# Environment variables win over the config file. All output goes to
# /tmp/rice-live.log as well.
#
# NOTE: output is English because the live console cannot render Chinese.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIG_FILE=""
FROM_STEP=""
ASSUME_YES="${ASSUME_YES:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --config=*) CONFIG_FILE="${1#*=}"; shift ;;
        --from) FROM_STEP="$2"; shift 2 ;;
        --from=*) FROM_STEP="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        --list-disks) LIST_DISKS=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
export DRY_RUN ASSUME_YES

[[ -n "$CONFIG_FILE" ]] && load_env_file "$CONFIG_FILE"

if [[ -n "$FROM_STEP" ]]; then
    valid=0
    for s in partition bootstrap chroot deploy modules; do
        [[ "$s" == "$FROM_STEP" ]] && valid=1
    done
    [[ "$valid" == "1" ]] || die "--from must be partition|bootstrap|chroot|deploy|modules"
fi

# --- Defaults (after config/env so those win) ---------------------------------
: "${DISK:=}"
: "${ESP_SIZE:=1G}"
: "${SYS_HOSTNAME:=arch}"
: "${USERNAME:=arch}"
: "${USER_PASSWORD:=}"
: "${ROOT_PASSWORD:=}"
: "${TIMEZONE:=Asia/Shanghai}"
: "${LOCALE:=zh_CN.UTF-8}"
: "${KEYMAP:=us}"
: "${PROFILE:=full}"                 # full | smoke | base
: "${FILE_MANAGER:=}"                 # thunar | gds | gds-portal | empty = prompt
: "${SWAP:=zram}"                    # zram | none
: "${BTRFS_OPTS:=compress=zstd:3,noatime}"
: "${GRUB_REMOVABLE:=0}"             # 1 only for VMs / removable installs
: "${RICE_REPO:=$REPO_ROOT}"         # directory or git URL
: "${RICE_REF:=}"
: "${LOWSPEC_REPO:=https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles.git}"
: "${LOWSPEC_REF:=}"
: "${MIRROR_URL:=}"
: "${ALLOW_WIPE:=no}"
: "${REBOOT:=0}"
: "${SKIP_NET_CHECK:=0}"
: "${MNT:=/mnt}"
: "${FIRMWARE:=}"                    # uefi | bios | empty = auto-detect

if [[ -z "$FIRMWARE" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        FIRMWARE=uefi
    elif [[ -d /sys/firmware/efi ]]; then
        FIRMWARE=uefi
    else
        FIRMWARE=bios
    fi
fi

export DISK ESP_SIZE SYS_HOSTNAME USERNAME USER_PASSWORD ROOT_PASSWORD TIMEZONE LOCALE \
       KEYMAP PROFILE FILE_MANAGER SWAP BTRFS_OPTS GRUB_REMOVABLE RICE_REPO RICE_REF \
       LOWSPEC_REPO LOWSPEC_REF MIRROR_URL ALLOW_WIPE REBOOT SKIP_NET_CHECK MNT FIRMWARE

STEPS=(partition bootstrap chroot deploy modules)
STEP_FILES=(10-partition.sh 20-bootstrap.sh 30-chroot-base.sh 40-deploy.sh 50-modules.sh)

list_disks() {
    say "Candidate disks (whole disks only; loop/rom excluded):"
    lsblk -d -e 7,11 -o NAME,SIZE,MODEL,TYPE
    say ""
    say "Use the whole-disk path, e.g. /dev/nvme0n1 or /dev/sda."
}

if [[ "${LIST_DISKS:-0}" == "1" ]]; then
    list_disks
    exit 0
fi

# Disk that the live ISO itself boots from; must never be wiped.
live_source_disk() {
    local src parent
    src="$(findmnt -n -o SOURCE /run/archiso/bootmnt 2>/dev/null || true)"
    [[ -n "$src" ]] || return 1
    parent="$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)"
    if [[ -n "$parent" ]]; then
        printf '/dev/%s\n' "$parent"
    else
        printf '%s\n' "$src"
    fi
}

network_ok() {
    curl -fsS --max-time 8 https://archlinux.org/ -o /dev/null 2>/dev/null
}

preconditions() {
    step "preconditions"
    if [[ "$DRY_RUN" != "1" ]]; then
        [[ "$(id -u)" -eq 0 ]] || die "Must run as root"
        [[ -d /run/archiso ]] || die "Not an Arch live environment (/run/archiso missing)"
        for cmd in pacstrap sgdisk partprobe mkfs.btrfs arch-chroot genfstab curl lsblk; do
            command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
        done
        if [[ "$FIRMWARE" == "uefi" ]]; then
            command -v mkfs.fat >/dev/null 2>&1 || die "Missing command: mkfs.fat (dosfstools)"
        fi

        if [[ -z "$DISK" ]]; then
            list_disks
            [[ -t 0 ]] || die "DISK is not set; pass DISK=/dev/... or use --config"
            read -r -p "Enter disk path to install to: " DISK
            export DISK
        fi
        [[ -b "$DISK" ]] || die "Not a block device: $DISK"

        local live_disk
        live_disk="$(live_source_disk || true)"
        if [[ -n "$live_disk" && "$live_disk" == "$DISK" ]]; then
            die "Refusing to install over the live medium ($live_disk). Pick another disk."
        fi

        if [[ "$SKIP_NET_CHECK" != "1" ]] && ! network_ok; then
            die "No network. Wired: dhcpcd should already work. Wi-Fi: run iwctl first, or set SKIP_NET_CHECK=1."
        fi
    fi

    case "$PROFILE" in full|smoke|base) ;; *) die "PROFILE must be full|smoke|base" ;; esac

    # 文件管理器只影响 Minimal Niri（full profile）。交互安装在这里一次性问清，
    # 避免等到 04n 才发现选错；base/smoke 不需要。
    if [[ "$PROFILE" == "full" ]]; then
        case "${FILE_MANAGER:-}" in
            thunar|gds|gds-portal) ;;
            "")
                if [[ -t 0 && "$DRY_RUN" != "1" ]]; then
                    say ""
                    say "File manager for Minimal Niri:"
                    say "  1) Thunar (default, GTK)"
                    say "  2) GDS Files (experimental, Rust/GPUI)"
                    say "  3) GDS Files + GDS Portal (experimental, file chooser too)"
                    local fm_pick
                    read -r -p "Select [1-3, Enter=1]: " fm_pick || fm_pick=1
                    case "${fm_pick:-1}" in
                        2) FILE_MANAGER=gds ;;
                        3) FILE_MANAGER=gds-portal ;;
                        *) FILE_MANAGER=thunar ;;
                    esac
                else
                    FILE_MANAGER=thunar
                fi
                export FILE_MANAGER
                ;;
            *) die "FILE_MANAGER must be thunar|gds|gds-portal" ;;
        esac
    fi
    if [[ "$PROFILE" != "base" && "$DRY_RUN" != "1" ]]; then
        [[ -n "$USER_PASSWORD" && "$USER_PASSWORD" != "CHANGE_ME" ]] \
            || die "Set USER_PASSWORD in the config (placeholder CHANGE_ME is rejected)"
    fi
    say "  profile : $PROFILE"
    say "  firmware: $FIRMWARE"
    say "  disk    : ${DISK:-<unset>}"
    say "  user    : $USERNAME@$SYS_HOSTNAME"
    say "  mirror  : ${MIRROR_URL:-ISO default}"
    say "  swap    : $SWAP"
    say "  filemgr : ${FILE_MANAGER:-thunar}"
}

should_run() {
    local step_name="$1"
    [[ -z "$FROM_STEP" ]] && return 0
    local target="$FROM_STEP" i found=0
    for i in "${STEPS[@]}"; do
        [[ "$i" == "$target" ]] && found=1
        [[ "$found" == "1" && "$i" == "$step_name" ]] && return 0
    done
    return 1
}

for i in "${!STEP_FILES[@]}"; do
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/steps/${STEP_FILES[$i]}"
done

preconditions
for i in "${!STEPS[@]}"; do
    name="${STEPS[$i]}"
    should_run "$name" || { warn "skip step: $name"; continue; }
    "step_${name}"
done

step "done"
say "Install finished. Log: $LOG_FILE"
say "After reboot: ssh -p ${VM_SSH_PORT:-2222} ${USERNAME}@localhost (if VM)"
if [[ "$REBOOT" == "1" ]]; then
    [[ "$DRY_RUN" == "1" ]] || run systemctl reboot
fi
