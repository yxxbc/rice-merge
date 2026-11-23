#!/usr/bin/env bash
# 04n-lowspec-niri.sh — shorin 中文底座 + Low-Spec 视觉层的合并步骤
#
# 本仓库是 shorin-arch-setup 的 fork（见 UPSTREAM.md）。04n 是本地新增的模块，
# 由 install.sh 在 04j-minimal-niri.sh 之后自动调用。
#
# 用法：
#   sudo bash 04n-lowspec-niri.sh          # 应用（幂等，可重复执行）
#   bash 04n-lowspec-niri.sh check         # 只做契约预检，不写盘
#   bash 04n-lowspec-niri.sh plan          # 预检 + 打印将要做什么
#   sudo bash 04n-lowspec-niri.sh undo     # 按 manifest 回滚本脚本的改动
#
# 输入（均有默认值，可用环境变量覆盖）：
#   RICE_ROOT        shorin 树根；默认脚本上一级
#   RICE_HOME        目标家目录；默认按 shorin 的方式探测用户
#   RICE_USER        目标用户（配合 RICE_HOME 用于测试）
#   LOWSPEC_DIR      Low-Spec 仓库；默认 $RICE_ROOT/low-spec-dotfiles
#   OVERLAY_DIR      overlay 目录；默认 $RICE_ROOT/resources/rice-merge
#   PATCHER          niri_patch.py 路径
#   RICE_TOOLS_DIR   common.sh 所在目录
#   AUR_HELPER       默认 paru
#   RICE_FILE_MANAGER      thunar（默认）| gds（GDS Files，实验）
#   RICE_GDS_PORTAL=1      装 xdg-desktop-portal-gds 并接管 FileChooser（需 gds）
#   RICE_GDS_PKG / RICE_GDS_PORTAL_PKG
#                          本地 .pkg.tar.zst（离线安装；跳过后下载校验）
#   GDS_FILES_VERSION / GDS_FILES_SHA256 / GDS_PORTAL_VERSION / GDS_PORTAL_SHA256
#                          版本 pin（默认 0.0.5，sha256 已内置）
#   GDS_CACHE_DIR          下载缓存，默认 /var/cache/rice-merge
#   RICE_SKIP_PACKAGES=1   跳过 pacman/paru（VM smoke / 只验证合并逻辑）
#   RICE_SKIP_DM=1         不问 DM，按默认装 ly
#   RICE_NO_DM=1           不安装/不启用 DM
#   RICE_ALLOW_NONROOT=1   测试用：跳过 root 检查
#   RICE_LENIENT=1         patch 失败只告警（不建议）
#   RICE_DRY_RUN=1         只打印，不写盘
#
# 依赖：python3；shorin 的 00-utils.sh（可选，缺失时用 scripts/lib/common.sh 的回退）

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# --- 1. 定位并加载公共库 -----------------------------------------------------
RICE_LIB=""
if [[ -n "${RICE_TOOLS_DIR:-}" && -f "$RICE_TOOLS_DIR/common.sh" ]]; then
    RICE_LIB="$RICE_TOOLS_DIR/common.sh"
elif [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    RICE_LIB="$SCRIPT_DIR/lib/common.sh"
elif [[ -f "$PARENT_DIR/scripts/lib/common.sh" ]]; then
    RICE_LIB="$PARENT_DIR/scripts/lib/common.sh"
fi
if [[ -z "$RICE_LIB" ]]; then
    echo "fatal: 找不到 common.sh（用 RICE_TOOLS_DIR 指定）" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$RICE_LIB"

# shorin 的工具库提供 detect_target_user / exe / as_user / setup_ly 等；缺失也能跑
if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/00-utils.sh"
fi

# 以普通用户运行（check/plan 或测试）时，runuser 不可用或没必要
if [[ "$(id -u)" -ne 0 ]]; then
    as_user() { "$@"; }
fi

# --- 2. 路径解析 -------------------------------------------------------------
RICE_ROOT="${RICE_ROOT:-$PARENT_DIR}"
LOWSPEC_DIR="${LOWSPEC_DIR:-$RICE_ROOT/low-spec-dotfiles}"
MINIMAL_DIR="${MINIMAL_DIR:-$RICE_ROOT/minimal-niri-dotfiles}"

if [[ -n "${OVERLAY_DIR:-}" ]]; then
    :
elif [[ -d "$RICE_ROOT/resources/rice-merge" ]]; then
    OVERLAY_DIR="$RICE_ROOT/resources/rice-merge"
else
    OVERLAY_DIR="$PARENT_DIR/resources/rice-merge"
fi

if [[ -n "${PATCHER:-}" ]]; then
    :
elif [[ -f "$RICE_ROOT/tools/niri_patch.py" ]]; then
    PATCHER="$RICE_ROOT/tools/niri_patch.py"
else
    PATCHER="$PARENT_DIR/tools/niri_patch.py"
fi

AUR_HELPER="${AUR_HELPER:-paru}"
VERIFY_LIST="/tmp/shorin_install_verify.list"

# --- 文件管理器选择 ---------------------------------------------------------
RICE_FILE_MANAGER="${RICE_FILE_MANAGER:-thunar}"
RICE_GDS_PORTAL="${RICE_GDS_PORTAL:-0}"
GDS_FILES_VERSION="${GDS_FILES_VERSION:-0.0.5}"
GDS_FILES_SHA256="${GDS_FILES_SHA256:-e82e24a4965000218621864fabd157346610780fc280fee70f6fe79b37ad7144}"
GDS_PORTAL_VERSION="${GDS_PORTAL_VERSION:-$GDS_FILES_VERSION}"
GDS_PORTAL_SHA256="${GDS_PORTAL_SHA256:-22fa92685f26016d061d20fe87da9de393b7c20e8997fe53d257c63b29e98d67}"
GDS_RELEASE_BASE="${GDS_RELEASE_BASE:-https://github.com/GanDesktop/gds/releases/download}"
GDS_FILES_PKG_URL="${GDS_FILES_PKG_URL:-$GDS_RELEASE_BASE/v$GDS_FILES_VERSION/gds-files-$GDS_FILES_VERSION-1-x86_64.pkg.tar.zst}"
GDS_PORTAL_PKG_URL="${GDS_PORTAL_PKG_URL:-$GDS_RELEASE_BASE/v$GDS_PORTAL_VERSION/xdg-desktop-portal-gds-$GDS_PORTAL_VERSION-1-x86_64.pkg.tar.zst}"
GDS_CACHE_DIR="${GDS_CACHE_DIR:-/var/cache/rice-merge}"
GDS_DESKTOP_ID="io.github.GanDesktop.GdsFiles.desktop"

set_target_dirs() {
    NIRI="$HOME_DIR/.config/niri"
    WB="$HOME_DIR/.config/waybar"
}

# --- 3. 基础步骤 -------------------------------------------------------------
preflight() {
    section "preflight" "契约检查（只读）"
    require_cmd python3
    require_file "$PATCHER"
    require_dir "$LOWSPEC_DIR"
    require_file "$LOWSPEC_DIR/config/niri/rice-colors.kdl"
    require_file "$LOWSPEC_DIR/config/waybar/config.jsonc"
    require_file "$LOWSPEC_DIR/config/waybar/style.css"
    require_file "$LOWSPEC_DIR/config/matugen/config.toml"
    require_file "$LOWSPEC_DIR/config/matugen/templates/foot.ini"
    require_file "$LOWSPEC_DIR/config/matugen/templates/mako.conf"
    require_file "$LOWSPEC_DIR/config/matugen/templates/fuzzel.ini"
    require_file "$LOWSPEC_DIR/config/foot/foot.ini"
    require_file "$LOWSPEC_DIR/config/fuzzel/fuzzel.ini"
    require_file "$LOWSPEC_DIR/config/mako/config"
    require_file "$LOWSPEC_DIR/config/gtk-3.0/gtk.css"
    require_file "$LOWSPEC_DIR/config/gtk-4.0/gtk.css"
    require_file "$LOWSPEC_DIR/config/environment.d/90-wayland-perf.conf"
    require_dir "$OVERLAY_DIR"
    require_file "$OVERLAY_DIR/niri/rice-binds.kdl"
    require_file "$OVERLAY_DIR/environment.d/91-low-spec-fcitx.conf"

    require_file "$NIRI/config.kdl"
    require_file "$NIRI/binds.kdl"
    line_exists "$NIRI/config.kdl" 'include "layout.kdl"' ||
        line_exists "$NIRI/config.kdl" 'include "binds.kdl"' ||
        die "config.kdl 既没有 include \"layout.kdl\" 也没有 include \"binds.kdl\"：shorin 的 niri 配置结构变了"
    require_last_brace "$NIRI/binds.kdl"

    case "$RICE_FILE_MANAGER" in
        thunar|gds) ;;
        *) die "RICE_FILE_MANAGER 只支持 thunar / gds（当前: $RICE_FILE_MANAGER）" ;;
    esac
    if [[ "$RICE_GDS_PORTAL" == "1" && "$RICE_FILE_MANAGER" != "gds" ]]; then
        die "RICE_GDS_PORTAL=1 需要 RICE_FILE_MANAGER=gds"
    fi

    if [[ "${RICE_SKIP_PACKAGES:-0}" != "1" ]]; then
        require_cmd pacman
        require_cmd "$AUR_HELPER"
        if [[ "$RICE_FILE_MANAGER" == "gds" ]]; then
            [[ "$(uname -m)" == "x86_64" ]] ||
                die "GDS 目前只发布 x86_64 包（当前: $(uname -m)）；请用 RICE_FILE_MANAGER=thunar 或自行编译"
            if [[ -n "${RICE_GDS_PKG:-}" ]]; then
                require_file "$RICE_GDS_PKG"
            else
                require_cmd curl
                require_cmd sha256sum
            fi
            if [[ "$RICE_GDS_PORTAL" == "1" ]]; then
                if [[ -n "${RICE_GDS_PORTAL_PKG:-}" ]]; then
                    require_file "$RICE_GDS_PORTAL_PKG"
                else
                    require_cmd curl
                    require_cmd sha256sum
                fi
            fi
        fi
    fi

    [[ -f "$SCRIPT_DIR/00-utils.sh" ]] || warn "没有 00-utils.sh：以独立模式运行（回退 helper）"
    success "preflight 通过"
}

print_plan() {
    section "plan" "将执行的操作"
    cat <<EOF
  target user : ${TARGET_USER}
  home        : ${HOME_DIR}
  rice root   : ${RICE_ROOT}
  low-spec    : ${LOWSPEC_DIR}
  overlay     : ${OVERLAY_DIR}
  patcher     : ${PATCHER}
  file mgr    : ${RICE_FILE_MANAGER}$([[ "$RICE_GDS_PORTAL" == "1" ]] && echo " + gds portal")
  packages    : $([[ "${RICE_SKIP_PACKAGES:-0}" == "1" ]] && echo "skip" || echo "install")
EOF
    hr
}

# 调用 niri_patch.py，并在写盘前备份目标文件；失败默认 fatal
rice_patch() {
    local cmd="$1" target="$2" backup=""
    shift 2
    [[ -f "$target" ]] || die "patch 目标不存在: $target"
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] patch $cmd $target $*"
        return 0
    fi
    if ! rice_was_written "$target"; then
        rice_backup_once "$target"
    fi
    [[ -e "$target.rice.bak" ]] && backup="$target.rice.bak"
    if ! python3 "$PATCHER" "$cmd" "$target" "$@"; then
        if [[ "${RICE_LENIENT:-0}" == "1" ]]; then
            warn "niri_patch 失败（RICE_LENIENT=1，继续）: $cmd $target"
            return 0
        fi
        die "niri_patch 失败: $cmd $target $*"
    fi
    record_once file "$target" "$backup"
}

# 1/8 基础 dotfiles（仅在 shorin 树内且 04j 未跑时补齐）
step_base_dotfiles() {
    section "LowSpec Niri" "1/8 基础 dotfiles"
    if [[ -f "$HOME_DIR/.config/niri/config.kdl" ]]; then
        log "niri 配置已存在（04j 已铺过），跳过重复 force_copy"
    elif [[ -d "$MINIMAL_DIR" ]] && declare -F force_copy >/dev/null 2>&1; then
        force_copy "$MINIMAL_DIR/." "$HOME_DIR"
        chown_user "$HOME_DIR/.config"
    elif [[ -d "$MINIMAL_DIR" ]]; then
        log "跳过：没有 force_copy（独立模式）；基础 dotfiles 应由 shorin 的 04j 提供"
    else
        log "跳过：$MINIMAL_DIR 不存在（独立模式）"
    fi
}

# GDS 只发布预编译包（无 Arch 仓库），所以下载后必须校验 sha256 再 pacman -U。
# 离线安装可以先把包放到本机，用 RICE_GDS_PKG / RICE_GDS_PORTAL_PKG 指定。
gds_sha_ok() {
    local file="$1" sha="$2"
    ( cd "$(dirname "$file")" &&
      printf '%s  %s\n' "$sha" "$(basename "$file")" | sha256sum -c - >/dev/null 2>&1 )
}

gds_install_pkg() {
    local pkgname="$1" url="$2" sha="$3" local_pkg="${4:-}" label="$5"
    local dest="" tmp=""

    echo "$pkgname" >>"$VERIFY_LIST" 2>/dev/null || true

    if pacman -Qq "$pkgname" >/dev/null 2>&1; then
        log "$pkgname 已安装，跳过"
        return 0
    fi

    if [[ -n "$local_pkg" ]]; then
        require_file "$local_pkg"
        dest="$local_pkg"
        log "使用本地包: $dest（不再校验 sha256）"
    else
        mkdir -p "$GDS_CACHE_DIR" || die "无法创建缓存目录: $GDS_CACHE_DIR"
        dest="$GDS_CACHE_DIR/${url##*/}"
        if [[ -f "$dest" ]] && gds_sha_ok "$dest" "$sha"; then
            log "缓存命中: $dest"
        else
            tmp="$dest.part"
            rm -f "$tmp"
            exe curl -fL --retry 3 --connect-timeout 15 -o "$tmp" "$url" ||
                die "$label 下载失败: $url（可用 RICE_GDS_PKG / RICE_GDS_PORTAL_PKG 指定本地包）"
            if ! gds_sha_ok "$tmp" "$sha"; then
                rm -f "$tmp"
                die "$label sha256 校验失败（版本: ${GDS_FILES_VERSION}）；请检查下载源或覆盖 GDS_*_SHA256"
            fi
            mv -f "$tmp" "$dest"
        fi
    fi

    exe pacman -U --noconfirm --needed "$dest" || die "$label 安装失败"
    record_once pkg "$pkgname"
}

# 2/8 软件包
step_packages() {
    section "LowSpec Niri" "2/8 软件包"
    if [[ "${RICE_SKIP_PACKAGES:-0}" == "1" ]]; then
        warn "RICE_SKIP_PACKAGES=1：跳过 pacman/AUR 安装"
        return 0
    fi

    local pac_pkgs=(niri xwayland-satellite xdg-desktop-portal-gnome xdg-desktop-portal-gtk
                    fuzzel waybar polkit-gnome mako qt5-wayland qt6-wayland
                    foot fish starship
                    swaybg swayidle grim slurp
                    wl-clipboard cliphist jq python brightnessctl playerctl pamixer
                    # 皮肤字体 + 中文兜底：foot/fuzzel 用 JetBrainsMono Nerd Font，
                    # CJK 字形靠 Noto CJK 做 fontconfig fallback
                    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji)
    local aur_pkgs=(matugen wlogout rime-wanxiang-gram-zh-hans shorin-contrib-git)

    # 04j 会装 Thunar/Nautilus 作回退；这里只在默认文件管理器是 Thunar 时补齐 04n 的依赖。
    # 单跑 04n（没有 04j）时，选 gds 就不会再装 Thunar。
    if [[ "$RICE_FILE_MANAGER" == "thunar" ]]; then
        pac_pkgs+=(thunar tumbler ffmpegthumbnailer)
    else
        # gds-files 的 soname 依赖；pacman -U 不会自动补依赖，先显式装齐
        pac_pkgs+=(wayland libxkbcommon libxkbcommon-x11 libxcb libglvnd
                   vulkan-icd-loader xdg-desktop-portal shared-mime-info hicolor-icon-theme)
    fi

    echo "${pac_pkgs[*]}" >>"$VERIFY_LIST"
    exe pacman -S --noconfirm --needed "${pac_pkgs[@]}" || die "pacman 安装失败"

    echo "${aur_pkgs[*]}" >>"$VERIFY_LIST"
    exe as_user "$AUR_HELPER" -S --noconfirm --needed "${aur_pkgs[@]}" || die "AUR 安装失败"

    if [[ "$RICE_FILE_MANAGER" == "gds" ]]; then
        gds_install_pkg gds-files "$GDS_FILES_PKG_URL" "$GDS_FILES_SHA256" \
            "${RICE_GDS_PKG:-}" "GDS Files"
        if [[ "$RICE_GDS_PORTAL" == "1" ]]; then
            gds_install_pkg xdg-desktop-portal-gds "$GDS_PORTAL_PKG_URL" "$GDS_PORTAL_SHA256" \
                "${RICE_GDS_PORTAL_PKG:-}" "GDS Portal"
        fi
    fi
}

# 皮肤层全量铺开：Low-Spec 的 config/ 整棵树 -> ~/.config
# 唯一例外是 niri/config.kdl：那是整套 compositor 配置（硬编码 /home/yg、
# 不带 shorin 的中文输入/输出设置），视觉对齐只需要 rice-colors.kdl。
VISUAL_SKIP=("niri/config.kdl")

rice_put_visual_tree() {
    local src="$1" dst="$2" rel mode skip e
    while IFS= read -r rel; do
        skip=0
        for e in "${VISUAL_SKIP[@]}"; do
            if [[ "$rel" == "$e" ]]; then
                skip=1
                break
            fi
        done
        [[ "$skip" == "1" ]] && continue
        case "$rel" in
            *.sh|*/scripts/*) mode=755 ;;
            *) mode=644 ;;
        esac
        rice_put "$src/$rel" "$dst/$rel" "$mode"
    done < <(cd "$src" && find . -type f -print | sed 's|^\./||')
}

# 3/8 视觉层
step_visual() {
    section "LowSpec Niri" "3/8 视觉层（waybar/foot/fuzzel/mako/gtk/matugen）"
    rice_mkdir "$HOME_DIR/.config"
    rice_put_visual_tree "$LOWSPEC_DIR/config" "$HOME_DIR/.config"

    rice_mkdir "$HOME_DIR/.local/bin"
    local f
    for f in "$LOWSPEC_DIR"/local-bin/rice-*; do
        [[ -e "$f" ]] || continue
        rice_put "$f" "$HOME_DIR/.local/bin/$(basename "$f")" 755
    done
    rice_mkdir "$HOME_DIR/Pictures/_wallpapers"
    if compgen -G "$LOWSPEC_DIR/wallpapers/*" >/dev/null; then
        rice_put_tree_noclobber "$LOWSPEC_DIR/wallpapers" "$HOME_DIR/Pictures/_wallpapers"
    fi
    chown_user "$HOME_DIR/.config"
    chown_user "$HOME_DIR/.local/bin"
}

# 4/8 niri 配置合并
step_merge() {
    section "LowSpec Niri" "4/8 niri 配置合并"
    rice_patch binds "$NIRI/binds.kdl" "$OVERLAY_DIR/niri/rice-binds.kdl"
    if line_exists "$NIRI/config.kdl" 'include "layout.kdl"'; then
        rice_patch include "$NIRI/config.kdl" --name rice-colors.kdl --after layout.kdl
    else
        rice_patch include "$NIRI/config.kdl" --name rice-colors.kdl --after binds.kdl
    fi
    rice_patch sub "$WB/config.jsonc" --old /home/yg --new "$HOME_DIR"

    rice_put "$OVERLAY_DIR/environment.d/91-low-spec-fcitx.conf" \
        "$HOME_DIR/.config/environment.d/91-low-spec-fcitx.conf"
    patch_niri_session
    chown_user "$NIRI"
    chown_user "$WB"
}

# --- 文件管理器（GDS Files，可选） -----------------------------------------
# 统一处理“备份 + 写入 + 登记 manifest”，diff 函数只管内容。
rice_edit_file() {
    local target="$1" label="$2"
    shift 2
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] edit $target（$label）"
        return 0
    fi
    rice_mkdir "$(dirname "$target")"
    if ! rice_was_written "$target"; then
        rice_backup_once "$target"
    fi
    local backup=""
    [[ -e "$target.rice.bak" ]] && backup="$target.rice.bak"
    "$@" "$target" || die "编辑失败（$label）: $target"
    chown_user "$target"
    record_once file "$target" "$backup"
}

gds_set_mimeapps_default() {
    python3 - "$1" <<'PY'
import os
import sys

path = sys.argv[1]
entry = "inode/directory=io.github.GanDesktop.GdsFiles.desktop"
lines = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

out = []
section = None
replaced = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped
    if section == "[Default Applications]" and stripped.startswith("inode/directory="):
        if not replaced:
            out.append(entry)
            replaced = True
        continue
    out.append(line)

if not replaced:
    index = next(
        (i for i, line in enumerate(out) if line.strip() == "[Default Applications]"),
        None,
    )
    if index is None:
        out = ["[Default Applications]", entry, ""] + out
    else:
        out.insert(index + 1, entry)

with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out).rstrip("\n") + "\n")
PY
}

gds_set_portal_filechooser() {
    python3 - "$1" <<'PY'
import os
import sys

path = sys.argv[1]
key = "org.freedesktop.impl.portal.FileChooser=gds;"
lines = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

out = []
section = None
replaced = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped
    if section == "[preferred]" and stripped.startswith("org.freedesktop.impl.portal.FileChooser="):
        if not replaced:
            out.append(key)
            replaced = True
        continue
    out.append(line)

if not replaced:
    index = next((i for i, line in enumerate(out) if line.strip() == "[preferred]"), None)
    if index is None:
        if out and out[-1].strip():
            out.append("")
        out.extend(["[preferred]", "default=gnome;gtk;", key])
    else:
        out.insert(index + 1, key)

with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(out).rstrip("\n") + "\n")
PY
}

# 3.5/8：把 GDS Files 设为默认文件夹程序，并改 Mod+E
step_file_manager() {
    section "LowSpec Niri" "3.5/8 文件管理器（${RICE_FILE_MANAGER}）"
    if [[ "$RICE_FILE_MANAGER" != "gds" ]]; then
        log "保留上游默认（Thunar，缺失时回退 Nautilus）"
        return 0
    fi

    rice_edit_file "$HOME_DIR/.config/mimeapps.list" \
        "inode/directory -> GDS Files" gds_set_mimeapps_default

    rice_patch sub "$NIRI/binds.kdl" \
        --old 'spawn-sh "thunar || env GSK_RENDERER=gl nautilus";' \
        --new 'spawn "gds-files";'

    if [[ "$RICE_GDS_PORTAL" == "1" ]]; then
        rice_edit_file "$HOME_DIR/.config/xdg-desktop-portal/niri-portals.conf" \
            "FileChooser -> gds" gds_set_portal_filechooser
        log "重新登录后 xdg-desktop-portal 才会切到 GDS 文件选择器"
    fi
}

# 5/8 首次配色
step_render() {
    section "LowSpec Niri" "5/8 首次配色渲染"
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] rice-wallpaper random"
        return 0
    fi
    as_user sh -c 'command -v rice-wallpaper >/dev/null && rice-wallpaper random' ||
        warn "首次 matugen 渲染失败（进入会话后按 Mod+Ctrl+T 触发）"
}

# 6/8 显示管理器（shorin 默认 ly；04j 通常已装，这里做幂等补齐）
# niri-session 在装了 dinitctl 但没有 dinit 的系统上会走错分支，直接改用 niri --session
patch_niri_session() {
    local f=/usr/share/wayland-sessions/niri.desktop
    [[ -f "$f" ]] || return 0
    grep -q '^Exec=niri --session' "$f" && return 0
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] patch $f -> Exec=niri --session"
        return 0
    fi
    rice_backup_once "$f"
    sed -i 's|^Exec=.*|Exec=niri --session|' "$f"
    record_once file "$f" "$f.rice.bak"
    log "niri.desktop -> Exec=niri --session"
}

step_dm() {
    if [[ "${RICE_NO_DM:-0}" == "1" ]]; then
        log "RICE_NO_DM=1：不启用显示管理器"
        return 0
    fi
    if [[ "${RICE_SKIP_PACKAGES:-0}" == "1" ]]; then
        log "RICE_SKIP_PACKAGES=1：跳过显示管理器安装"
        return 0
    fi
    if [[ "${RICE_SKIP_DM:-0}" == "1" ]]; then
        export SKIP_DM=false
    elif declare -F check_dm_conflict >/dev/null 2>&1; then
        check_dm_conflict
    fi
    if [[ "${SKIP_DM:-false}" == "true" ]]; then
        log "跳过显示管理器（已有 DM 或用户选择跳过）"
    elif declare -F setup_ly >/dev/null 2>&1; then
        setup_ly
    else
        warn "找不到 setup_ly（独立模式）；请自行启用 ly/greetd"
    fi
}

# 7/8 结果校验：发现半合并就失败
step_verify() {
    section "LowSpec Niri" "7/8 结果校验"
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] 跳过结果校验"
        return 0
    fi
    line_exists "$NIRI/config.kdl" 'include "rice-colors.kdl"' ||
        die "config.kdl 没加上 rice-colors.kdl include"
    grep -q 'rice-merge binds begin' "$NIRI/binds.kdl" ||
        die "binds.kdl 没有 rice 键位块"
    braces_balanced "$NIRI/binds.kdl" || die "binds.kdl 花括号不平衡，合并失败"
    grep -q '/home/yg' "$WB/config.jsonc" && die "waybar config.jsonc 仍有 /home/yg 硬编码"
    [[ -f "$NIRI/rice-colors.kdl" ]] || die "rice-colors.kdl 缺失"

    local f
    for f in .config/foot/foot.ini .config/foot/rice-theme.ini \
             .config/fuzzel/fuzzel.ini .config/mako/config \
             .config/gtk-3.0/gtk.css .config/gtk-4.0/gtk.css \
             .config/environment.d/90-wayland-perf.conf \
             .config/matugen/templates/foot.ini \
             .config/matugen/templates/mako.conf \
             .config/matugen/templates/fuzzel.ini; do
        [[ -f "$HOME_DIR/$f" ]] || die "皮肤层缺少 $f（视觉层未对齐）"
    done
    grep -q '^\[templates\.foot\]' "$HOME_DIR/.config/matugen/config.toml" ||
        die "matugen 配置缺少 [templates.foot]：foot 不再跟随壁纸取色"
    grep -q '^\[templates\.mako\]' "$HOME_DIR/.config/matugen/config.toml" ||
        die "matugen 配置缺少 [templates.mako]：mako 不再跟随壁纸取色"

    if [[ "$RICE_FILE_MANAGER" == "gds" ]]; then
        grep -q "inode/directory=$GDS_DESKTOP_ID" "$HOME_DIR/.config/mimeapps.list" ||
            die "mimeapps.list 没有把 inode/directory 指向 GDS Files"
        grep -q 'spawn "gds-files"' "$NIRI/binds.kdl" ||
            die "binds.kdl 的 Mod+E 没有指向 gds-files"
        if [[ "$RICE_GDS_PORTAL" == "1" ]]; then
            grep -q 'org.freedesktop.impl.portal.FileChooser=gds;' \
                "$HOME_DIR/.config/xdg-desktop-portal/niri-portals.conf" ||
                die "niri-portals.conf 没有把 FileChooser 指向 gds"
            if [[ "${RICE_SKIP_PACKAGES:-0}" != "1" ]]; then
                pacman -Qq xdg-desktop-portal-gds >/dev/null 2>&1 ||
                    die "xdg-desktop-portal-gds 未安装"
            fi
        fi
        if [[ "${RICE_SKIP_PACKAGES:-0}" != "1" ]]; then
            pacman -Qq gds-files >/dev/null 2>&1 || die "gds-files 未安装"
            command -v gds-files >/dev/null 2>&1 || die "找不到 gds-files 可执行文件"
        fi
        success "GDS Files 已设为默认文件管理器"
    fi

    # 中文兜底：确认 fontconfig 里真的有 CJK 字形
    if command -v fc-list >/dev/null 2>&1; then
        if [[ -n "$(fc-list :lang=zh -f '%{family}\n' 2>/dev/null | head -n 1)" ]]; then
            success "中文字体可用（fc-list :lang=zh）"
        else
            warn "fc-list :lang=zh 为空：中文可能显示为方块（安装 noto-fonts-cjk）"
        fi
    fi

    if command -v niri >/dev/null 2>&1; then
        if niri -c "$NIRI/config.kdl" validate >/dev/null 2>&1 ||
            niri validate -c "$NIRI/config.kdl" >/dev/null 2>&1; then
            success "niri validate 通过"
        else
            if [[ "${RICE_LENIENT:-0}" == "1" ]]; then
                warn "niri validate 未通过（RICE_LENIENT=1，继续）；niri 可能无法启动"
            else
                die "niri validate 未通过：配置里有语法错误或重复键位（多由 binds.kdl 冲突引起）"
            fi
        fi
    fi
    success "合并结果校验通过"
}

# 8/8 完成
step_done() {
    section "LowSpec Niri" "8/8 完成"
    log "键位：Mod+Y 壁纸  Mod+Ctrl+Y 状态栏布局  Mod+F1 切换输入法  Mod+Shift+/ 全部键位"
    log "文件管理器：${RICE_FILE_MANAGER}$([[ "$RICE_GDS_PORTAL" == "1" ]] && echo '（+ GDS Portal）')"
    log "回滚：sudo bash $0 undo   （manifest: $RICE_MANIFEST）"
    if [[ "$RICE_FILE_MANAGER" == "gds" ]]; then
        warn "GDS Files 为实验性选择：不跟随 matugen 取色，归档/卷管理功能少于 Thunar"
    fi
    warn "视觉层已全量接管 foot/fuzzel/mako/gtk/waybar；首次登录后确认中文显示与字体"
}

# --- 4. 入口 -----------------------------------------------------------------
main() {
    local cmd="${1:-apply}"
    case "$cmd" in
        check|plan)
            rice_resolve_identity
            set_target_dirs
            preflight
            [[ "$cmd" == "plan" ]] && print_plan
            ;;
        undo)
            rice_resolve_identity
            rice_init_state
            rice_undo
            ;;
        apply)
            rice_require_root
            rice_resolve_identity
            set_target_dirs
            rice_init_state
            preflight
            print_plan

            step_base_dotfiles
            step_packages
            step_visual
            step_merge
            step_file_manager
            step_render
            step_dm
            step_verify
            step_done
            ;;
        -h|--help|help)
            sed -n '2,30p' "$0"
            ;;
        *)
            die "未知命令: $cmd（可用：apply / check / plan / undo）"
            ;;
    esac
}

main "$@"
