#!/usr/bin/env bash
# 30 — chroot 里的基础配置：时区/locale/主机名/用户/引导/zram

step_chroot() {
    step "30 chroot: base configuration"
    local script="$MNT/root/rice-base.sh"

    if [[ "$DRY_RUN" != "1" ]]; then
        {
            cat <<EOF
#!/bin/bash
set -uo pipefail
export LANG=en_US.UTF-8

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

sed -i 's/^#\s*en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#\s*zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "${KEYMAP}" > /etc/vconsole.conf
echo "${SYS_HOSTNAME}" > /etc/hostname

cat > /etc/hosts <<'HOSTS'
127.0.0.1 localhost
::1 localhost
127.0.1.1 ${SYS_HOSTNAME}.localdomain ${SYS_HOSTNAME}
HOSTS
EOF
            cat <<EOF
if ! id -u "${USERNAME}" >/dev/null 2>&1; then
    useradd -m -G wheel -s /bin/bash "${USERNAME}"
fi
EOF
            if [[ -n "$ROOT_PASSWORD" ]]; then
                printf 'echo %q | chpasswd\n' "root:$ROOT_PASSWORD"
            else
                echo 'passwd -l root || true'
            fi
            printf 'echo %q | chpasswd\n' "$USERNAME:$USER_PASSWORD"
            cat <<EOF
if ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
fi
if ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
    echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
fi

systemctl enable NetworkManager
systemctl enable fstrim.timer
systemctl enable systemd-timesyncd
EOF
            if [[ "$SWAP" == "zram" ]]; then
                cat <<'EOF'
pacman -S --noconfirm --needed zram-generator
cat > /etc/systemd/zram-generator.conf <<'ZRAM'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM
systemctl daemon-reload || true
EOF
            fi
            if [[ "$GRUB_REMOVABLE" == "1" ]]; then
                echo 'grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck'
            else
                echo 'grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck'
            fi
            cat <<'EOF'
grub-mkconfig -o /boot/grub/grub.cfg
mkinitcpio -P
EOF
        } >"$script"
        chmod +x "$script"
    fi

    run arch-chroot "$MNT" /bin/bash /root/rice-base.sh || die "chroot base configuration failed"
    [[ "$DRY_RUN" == "1" ]] || rm -f "$script"
}
