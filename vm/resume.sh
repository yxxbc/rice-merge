#!/usr/bin/env bash
# Runs INSIDE the Arch live ISO: mount the installed btrfs root and resume modules.
# Use when a long VM install was interrupted (QEMU killed / host sleep).
#
#   mkdir -p /repo
#   mount -t 9p -o trans=virtio,version=9p2000.L repo /repo
#   bash /repo/vm/resume.sh

set -uo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
[[ -d /run/archiso ]] || { echo "Not an Arch live environment." >&2; exit 1; }
[[ -b /dev/vda2 ]] || { echo "/dev/vda2 not found; adjust the device names." >&2; exit 1; }

umount -R /mnt 2>/dev/null || true
mkdir -p /mnt
mount -o subvol=@ /dev/vda2 /mnt || { echo "mount @ failed" >&2; exit 1; }
mkdir -p /mnt/home /mnt/boot
mount -o subvol=@home /dev/vda2 /mnt/home || { echo "mount @home failed" >&2; exit 1; }
mount /dev/vda1 /mnt/boot || { echo "mount ESP failed" >&2; exit 1; }

if [[ ! -f /mnt/opt/setup/rice/install.sh ]]; then
    echo "/opt/setup/rice missing: this disk was not installed by rice-merge" >&2
    exit 1
fi

cat >/mnt/root/rice-resume.sh <<'EOS'
#!/bin/bash
set -uo pipefail
export TARGET_USER=arch
export HOME_DIR=/home/arch
export RICE_SKIP_DM=1
export RICE_FILE_MANAGER="${RICE_FILE_MANAGER:-thunar}"
cd /opt/setup/rice || exit 1
echo "== resuming install.sh (completed modules in .install_progress are skipped)"
bash install.sh --unattended --desktop minimalniri --skip-reflector --no-reboot
status=$?
echo "== re-installing GRUB entry"
grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck || true
grub-mkconfig -o /boot/grub/grub.cfg || true
exit $status
EOS
chmod +x /mnt/root/rice-resume.sh

echo "== chroot resume"
arch-chroot /mnt /bin/bash /root/rice-resume.sh
status=$?
echo "== resume exit: $status"
exit $status
