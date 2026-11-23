#!/usr/bin/env bash
# 20 - pacstrap the base system and generate fstab

step_bootstrap() {
    step "20 bootstrap: pacstrap -> $MNT"

    if [[ -n "$MIRROR_URL" && "$DRY_RUN" != "1" ]]; then
        say "  mirror: $MIRROR_URL"
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.rice.bak 2>/dev/null || true
        { printf 'Server = %s\n' "$MIRROR_URL"; cat /etc/pacman.d/mirrorlist.rice.bak 2>/dev/null; } \
            >/etc/pacman.d/mirrorlist.tmp
        mv /etc/pacman.d/mirrorlist.tmp /etc/pacman.d/mirrorlist
    fi

    local ucode=""
    if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then
        ucode="intel-ucode"
    elif grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then
        ucode="amd-ucode"
    fi

    local pkgs=(base base-devel linux linux-firmware btrfs-progs sudo networkmanager
                git python rsync efibootmgr grub vim mesa)
    [[ -n "$ucode" ]] && pkgs+=("$ucode")

    run pacstrap -K "$MNT" "${pkgs[@]}" || die "pacstrap failed (check network/mirrors)"
    run_sh "genfstab -U '$MNT' >> '$MNT/etc/fstab'"
    if [[ -n "$MIRROR_URL" && "$DRY_RUN" != "1" ]]; then
        printf 'Server = %s\n' "$MIRROR_URL" >"$MNT/etc/pacman.d/mirrorlist"
        say "  target mirrorlist: $MIRROR_URL"
    fi

    if command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi 'nvidia'; then
        warn "NVIDIA GPU detected. mesa alone may not be enough: install nvidia-open/nvidia-utils"
        warn "and enable modeset, or run 03b-gpu-driver.sh after the first boot."
    fi

    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -f "$MNT/etc/fstab" ]] || die "fstab was not generated"
        say "  fstab: $(wc -l <"$MNT/etc/fstab") lines"
    fi
}
