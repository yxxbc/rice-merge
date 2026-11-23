#!/usr/bin/env bash
# 在 Arch live ISO 里用一条在线命令安装（不需要 9p 共享）。
#
#   curl -fsSL https://raw.githubusercontent.com/yxxbc/rice-merge/main/live/remote-install.sh \
#     | bash -s -- full
#
# 参数：full（默认，装到 niri 桌面）| smoke（只验证合并，无桌面）
#
# 它会先把仓库 clone 到 /tmp/rice-merge，再调用 vm/live-autoinstall.sh。
# 真机同样适用；分区前仍会有 5 秒倒计时可 Ctrl+C。

set -euo pipefail

PROFILE="${1:-full}"
REPO_URL="${RICE_REPO_URL:-https://github.com/yxxbc/rice-merge.git}"
DIR="${RICE_DIR:-/tmp/rice-merge}"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root in the live ISO." >&2; exit 1; }
[[ -d /run/archiso ]] || { echo "Not an Arch live environment." >&2; exit 1; }
case "$PROFILE" in smoke|full) ;; *) echo "Usage: $0 [smoke|full]" >&2; exit 2 ;; esac

if ! command -v git >/dev/null 2>&1; then
    echo "==> Installing git"
    pacman -Sy --noconfirm --needed git
fi

echo "==> Cloning $REPO_URL -> $DIR"
rm -rf "$DIR"
git clone --depth=1 "$REPO_URL" "$DIR"

echo "==> Starting unattended install (profile=$PROFILE)"
exec bash "$DIR/vm/live-autoinstall.sh" "$PROFILE" </dev/tty
