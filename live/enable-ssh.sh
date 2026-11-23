#!/usr/bin/env bash
# Enable sshd in the Arch live ISO.
#
# Why: the live console cannot render Chinese. Running the installer over SSH
# from a normal terminal gives you UTF-8 logs (and scrollback) instead of boxes.
#
#   bash live/enable-ssh.sh
#   # from another machine:
#   ssh -p 2222 root@<live-ip>      # VM forwards 2222; real hardware uses 22
#
# Then on the live box: bash /repo/live/install.sh --config /repo/live/install.env

set -uo pipefail

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root (live ISO)." >&2; exit 1; }

echo "==> Installing and starting openssh"
pacman -Sy --noconfirm --needed openssh || exit 1
systemctl start sshd || exit 1

echo "==> Set a root password for the live session"
passwd root || exit 1

echo ""
echo "==> Connect from another machine (UTF-8 terminal):"
ip -4 addr show scope global 2>/dev/null | awk '/inet /{print "    ssh root@" $2}' | sed 's|/.*||'
echo "    (VM with hostfwd: ssh -p 2222 root@localhost)"
echo ""
echo "On the live box, mount the repo if needed:"
echo "    mkdir -p /repo"
echo "    mount -t 9p -o trans=virtio,version=9p2000.L repo /repo   # VM only"
