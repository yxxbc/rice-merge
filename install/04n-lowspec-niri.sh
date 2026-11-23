#!/usr/bin/env bash
# 04n-lowspec-niri.sh — shorin-arch-setup 的桌面步骤：shorin 中文底座 + Low-Spec 视觉层
#
# 由 rice-merge 的 `make deploy SHORIN=/path/to/shorin-arch-setup` 自动部署到
# <shorin>/scripts/ 下，依赖：
#   <shorin>/low-spec-dotfiles/            （git clone Low-Spec-Niri-Dotfiles）
#   <shorin>/resources/niri-merge-overlay/ （overlay/ 的副本）
#   <shorin>/resources/niri-merge-tools/niri_patch.py
#
# 环境变量：LOWSPEC_DIR、OVERLAY_DIR、PATCHER、AUR_HELPER

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR." >&2
    exit 1
fi

LOWSPEC_DIR="${LOWSPEC_DIR:-$PARENT_DIR/low-spec-dotfiles}"
OVERLAY_DIR="${OVERLAY_DIR:-$PARENT_DIR/resources/niri-merge-overlay}"
PATCHER="${PATCHER:-$PARENT_DIR/resources/niri-merge-tools/niri_patch.py}"
AUR_HELPER="${AUR_HELPER:-paru}"
VERIFY_LIST="/tmp/shorin_install_verify.list"

check_root || exit 1
detect_target_user
if [[ -z "${TARGET_USER:-}" || ! -d "${HOME_DIR:-}" ]]; then
    echo "Error: target user invalid or home directory missing." >&2
    exit 1
fi
info_kv "Target User" "$TARGET_USER"
check_dm_conflict

for path in "$LOWSPEC_DIR/config/niri" "$OVERLAY_DIR/niri" "$PATCHER"; do
    if [[ ! -e "$path" ]]; then
        echo "Error: 缺少 $path（先跑 make deploy 并 clone Low-Spec 仓库）" >&2
        exit 1
    fi
done

rm -f "$VERIFY_LIST"
chown_user() { chown -R "$TARGET_USER": "$1" 2>/dev/null || true; }
put() { install -Dm "${3:-644}" "$1" "$2"; chown_user "$2"; }
patch() { python3 "$PATCHER" "$@" || warn "niri_patch 执行失败：$*"; }

# ==============================================================================
section "LowSpec Niri" "1/6 基础 dotfiles（shorin minimal）"
force_copy "$PARENT_DIR/minimal-niri-dotfiles/." "$HOME_DIR"
chown_user "$HOME_DIR/.config"

# ==============================================================================
section "LowSpec Niri" "2/6 软件包"
PAC_PKGS=(niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk
          fuzzel waybar polkit-gnome mako qt5-wayland qt6-wayland
          foot fish starship thunar tumbler ffmpegthumbnailer
          swaybg swayidle wlogout grim slurp
          wl-clipboard cliphist jq python brightnessctl playerctl pamixer)
echo "${PAC_PKGS[*]}" >>"$VERIFY_LIST"
exe pacman -S --noconfirm --needed "${PAC_PKGS[@]}"

AUR_PKGS=(matugen linuxqq-wayland-fix-git rime-wanxiang-gram-zh-hans shorin-contrib-git)
echo "${AUR_PKGS[*]}" >>"$VERIFY_LIST"
exe as_user "$AUR_HELPER" -S --noconfirm --needed "${AUR_PKGS[@]}"

# ==============================================================================
section "LowSpec Niri" "3/6 视觉层（Waybar / matugen / rice-*）"
WB="$HOME_DIR/.config/waybar"
mkdir -p "$WB"

# 保留 shorin 的 waybar 配置，再换成 Low-Spec 的 15 套布局
[[ -f "$WB/config.jsonc" ]] && cp -a "$WB/config.jsonc" "$WB/config.jsonc.shorin.bak"
[[ -f "$WB/style.css"    ]] && cp -a "$WB/style.css"    "$WB/style.css.shorin.bak"

put "$LOWSPEC_DIR/config/waybar/config.jsonc" "$WB/config.jsonc"
put "$LOWSPEC_DIR/config/waybar/style.css"    "$WB/style.css"
rsync -a "$LOWSPEC_DIR/config/waybar/scripts/" "$WB/scripts/"
rsync -a "$LOWSPEC_DIR/config/waybar/themes/"  "$WB/themes/"
chown_user "$WB"

# matugen：只启用 waybar / niri / gtk，foot 与 mako 仍归 shorin 管
MT="$HOME_DIR/.config/matugen"
mkdir -p "$MT/templates"
put "$LOWSPEC_DIR/config/matugen/config.toml" "$MT/config.toml"
for t in colors.css niri-colors.kdl gtk.css; do
    [[ -f "$LOWSPEC_DIR/config/matugen/templates/$t" ]] && \
        put "$LOWSPEC_DIR/config/matugen/templates/$t" "$MT/templates/$t"
done
patch matugen "$MT/config.toml" --section foot --section mako --section fuzzel
chown_user "$MT"

mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/niri-rice" "$HOME_DIR/Pictures/_wallpapers"
install -m755 "$LOWSPEC_DIR"/local-bin/rice-* "$HOME_DIR/.local/bin/"
rsync -a "$LOWSPEC_DIR/config/niri-rice/" "$HOME_DIR/.config/niri-rice/"
if compgen -G "$LOWSPEC_DIR/wallpapers/*" >/dev/null; then
    cp -rn "$LOWSPEC_DIR"/wallpapers/* "$HOME_DIR/Pictures/_wallpapers/"
fi
chown_user "$HOME_DIR/.local/bin"
chown_user "$HOME_DIR/.config/niri-rice"
chown_user "$HOME_DIR/Pictures/_wallpapers"

# ==============================================================================
section "LowSpec Niri" "4/6 niri 配置合并"
NIRI="$HOME_DIR/.config/niri"
put "$LOWSPEC_DIR/config/niri/rice-colors.kdl" "$NIRI/rice-colors.kdl"
patch binds   "$NIRI/binds.kdl"  "$OVERLAY_DIR/niri/rice-binds.kdl"
patch include "$NIRI/config.kdl" --name rice-colors.kdl --after layout.kdl
patch sub     "$WB/config.jsonc" --old /home/yg --new "$HOME_DIR"
put "$OVERLAY_DIR/environment.d/91-low-spec-fcitx.conf" \
    "$HOME_DIR/.config/environment.d/91-low-spec-fcitx.conf"
chown_user "$NIRI"
chown_user "$WB"

# ==============================================================================
section "LowSpec Niri" "5/6 首次配色渲染"
as_user sh -c 'command -v rice-wallpaper >/dev/null && rice-wallpaper random' \
    || warn "首次 matugen 渲染失败（进入会话后按 Mod+Ctrl+T 触发）"

# ==============================================================================
section "LowSpec Niri" "6/6 完成"
log "桌面已就位。注销后从 ly 进入 niri 会话。"
log "键位：Mod+Y 壁纸  Mod+Ctrl+Y 状态栏布局  Mod+F1 切换输入法  Mod+Shift+/ 全部键位"
warn "kdl 语法、matugen 对 shorin 字体的影响、hyprlock 是否已装，需要真机确认"
