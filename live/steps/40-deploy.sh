#!/usr/bin/env bash
# 40 - copy this repository and the Low-Spec visual layer into the new system

copy_repo() {
    local src="$1" dest="$2" ref="$3"
    run rm -rf "$dest"
    if [[ -d "$src" ]]; then
        say "  source: local directory $src"
        run mkdir -p "$dest"
        # Exclude .git / cloned Low-Spec / VM disks / local password config
        run_sh "tar -C '$src' \
            --exclude=.git \
            --exclude=low-spec-dotfiles \
            --exclude='vm/*.qcow2' \
            --exclude=vm/edk2-vars.fd \
            --exclude=vm/serial.log \
            --exclude=live/install.env \
            -cf - . | tar -C '$dest' -xf -" || die "Failed to copy the repository"
        return 0
    fi
    run git clone --depth=1 "$src" "$dest" || die "git clone failed: $src"
    if [[ -n "$ref" ]]; then
        run git -C "$dest" fetch --depth=1 origin "$ref" || die "Failed to fetch $ref"
        run git -C "$dest" checkout -q FETCH_HEAD || die "Failed to checkout $ref"
    fi
}

step_deploy() {
    step "40 deploy: $MNT/opt/setup/rice"
    local dest="$MNT/opt/setup/rice"

    run mkdir -p "$MNT/opt/setup"
    copy_repo "$RICE_REPO" "$dest" "$RICE_REF"

    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -f "$dest/install.sh" ]] || die "Deployed tree is missing install.sh"
        [[ -f "$dest/scripts/04n-lowspec-niri.sh" ]] || die "Deployed tree is missing 04n"
        [[ -d "$dest/resources/rice-merge" ]] || die "Deployed tree is missing resources/rice-merge"
    fi

    if [[ -d "$dest/low-spec-dotfiles/.git" ]]; then
        say "  low-spec: already cloned"
    else
        if ! command -v git >/dev/null 2>&1; then
            say "  git missing on live, installing it"
            run pacman -Sy --noconfirm --needed git || die "git is required to clone Low-Spec"
        fi
        run git clone --depth=1 "$LOWSPEC_REPO" "$dest/low-spec-dotfiles" \
            || die "Low-Spec clone failed (no LICENSE, so it is never vendored)"
    fi
    if [[ -n "$LOWSPEC_REF" ]]; then
        run git -C "$dest/low-spec-dotfiles" fetch --depth=1 origin "$LOWSPEC_REF"
        run git -C "$dest/low-spec-dotfiles" checkout -q FETCH_HEAD
    fi

    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -f "$dest/low-spec-dotfiles/config/waybar/config.jsonc" ]] \
            || die "Low-Spec tree does not look right"
    fi
}
