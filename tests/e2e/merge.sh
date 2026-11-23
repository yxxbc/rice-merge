#!/usr/bin/env bash
# 端到端测试：用仓库里真实的 shorin 树 + 真实 04n，在假 HOME 上验证
#   1. 合并结果正确（include / binds / waybar / matugen）
#   2. 重跑幂等（文件内容不变）
#   3. undo 能回到合并前的状态
#   4. 契约被破坏时 check 立即失败
#
# 不需要 root、不需要 Arch：系统命令用 stub，Low-Spec 用最小子集。
# 运行：bash tests/e2e/merge.sh

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/rice-e2e.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/home"
BIN="$TMP/bin"
LS="$TMP/low-spec-dotfiles"
mkdir -p "$HOME_DIR/.config" "$BIN" "$LS"

pass=0
fail() { printf '\n[FAIL] %s\n' "$*" >&2; exit 1; }
ok() { pass=$((pass + 1)); printf '  ok  %s\n' "$*"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "$1 不包含: $2"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "$1 仍包含: $2"; }
assert_file() { [[ -f "$1" ]] || fail "缺少文件: $1"; }
assert_no_file() { [[ ! -e "$1" ]] || fail "文件应被删除: $1"; }

# --- stub 命令 -----------------------------------------------------------------
cat >"$BIN/paru" <<'EOF'
#!/bin/sh
echo "stub paru $*" >>"$RICE_E2E_LOG"
exit 0
EOF
cat >"$BIN/rice-wallpaper" <<'EOF'
#!/bin/sh
echo "stub rice-wallpaper $*" >>"$RICE_E2E_LOG"
exit 0
EOF
chmod +x "$BIN/paru" "$BIN/rice-wallpaper"
export RICE_E2E_LOG="$TMP/commands.log"

# --- 假 HOME：用仓库里真实的 shorin minimal dotfiles ---------------------------
cp -a "$REPO_ROOT/minimal-niri-dotfiles/." "$HOME_DIR/"
# 让 sub 有活可干：模拟 Low-Spec 的硬编码
# 让 sub 有活可干：模拟 Low-Spec 的 /home/yg 硬编码（JSONC 支持 // 注释）
printf '\n// scripts: /home/yg/.config/waybar/scripts/logo.sh\n' >>"$HOME_DIR/.config/waybar/config.jsonc"
ORIGINAL_WAYBAR="$(cat "$HOME_DIR/.config/waybar/config.jsonc")"

# --- Low-Spec 最小子集 ---------------------------------------------------------
mkdir -p "$LS/config/niri" "$LS/config/waybar/scripts" "$LS/config/waybar/themes/theme-a" \
         "$LS/config/matugen/templates" "$LS/config/niri-rice" "$LS/local-bin" "$LS/wallpapers" \
         "$LS/config/foot" "$LS/config/fuzzel" "$LS/config/mako" \
         "$LS/config/gtk-3.0" "$LS/config/gtk-4.0" "$LS/config/environment.d"
printf 'window-rule {\n    background-color "rgba(0,0,0,0.8)"\n}\n' >"$LS/config/niri/rice-colors.kdl"
cat >"$LS/config/waybar/config.jsonc" <<'EOF'
{
  "layer": "top",
  "modules-left": ["custom/logo"],
  "custom/logo": { "exec": "/home/yg/.config/waybar/scripts/logo.sh" }
}
EOF
printf '.bar { color: #fff; }\n' >"$LS/config/waybar/style.css"
printf '#!/bin/sh\nexit 0\n' >"$LS/config/waybar/scripts/theme-selector.sh"
printf '{ "layer": "top" }\n' >"$LS/config/waybar/themes/theme-a/config.jsonc"
printf '.a{}\n' >"$LS/config/waybar/themes/theme-a/style.css"
cat >"$LS/config/matugen/config.toml" <<'EOF'
[config]
reload_apps = false

[templates.waybar]
input_path = 'colors.css'
output_path = '~/.config/waybar/colors.css'

[templates.foot]
output_path = '~/.config/foot/rice-theme.ini'

[templates.mako]
output_path = '~/.config/mako/config'

[templates.fuzzel]
output_path = '~/.config/fuzzel/fuzzel.ini'

[templates.niri]
output_path = '~/.config/niri/rice-colors.kdl'
EOF
printf '/* colors */\n' >"$LS/config/matugen/templates/colors.css"
printf '// niri\n' >"$LS/config/matugen/templates/niri-colors.kdl"
printf '/* gtk */\n' >"$LS/config/matugen/templates/gtk.css"
printf '[colors-dark]\nbackground=181c20\n' >"$LS/config/matugen/templates/foot.ini"
printf 'font=Noto Sans 11\n' >"$LS/config/matugen/templates/mako.conf"
printf '[colors]\nbackground=#262a2ef0\n' >"$LS/config/matugen/templates/fuzzel.ini"
# 皮肤层其余配置
printf 'font=JetBrainsMono Nerd Font:size=11\ninclude=~/.config/foot/rice-theme.ini\n' \
    >"$LS/config/foot/foot.ini"
printf '[colors-dark]\nbackground=181c20\n' >"$LS/config/foot/rice-theme.ini"
printf '[main]\nfont=JetBrainsMono Nerd Font:size=12\n' >"$LS/config/fuzzel/fuzzel.ini"
printf 'font=Noto Sans 11\n' >"$LS/config/mako/config"
printf '/* gtk3 skin */\n' >"$LS/config/gtk-3.0/gtk.css"
printf '/* gtk4 skin */\n' >"$LS/config/gtk-4.0/gtk.css"
printf 'MOZ_ENABLE_WAYLAND=1\n' >"$LS/config/environment.d/90-wayland-perf.conf"
printf '/* waybar colors */\n' >"$LS/config/waybar/colors.css"
# 这个文件不应被部署：niri 主配置归 shorin
printf '// low-spec niri config (must not be deployed)\ninclude "layout.kdl"\n' \
    >"$LS/config/niri/config.kdl"
printf '{}\n' >"$LS/config/niri-rice/wlogout-layout.json"
printf '#!/bin/sh\necho rice-paper\n' >"$LS/local-bin/rice-paper"
printf '#!/bin/sh\necho rice-wallpaper\n' >"$LS/local-bin/rice-wallpaper"
printf 'PNG\n' >"$LS/wallpapers/wall.png"

run_04n() {
    RICE_ALLOW_NONROOT=1 \
    RICE_USER="$(id -un)" \
    RICE_HOME="$HOME_DIR" \
    LOWSPEC_DIR="$LS" \
    MINIMAL_DIR="$TMP/nonexistent" \
    RICE_SKIP_PACKAGES=1 \
    RICE_NO_DM=1 \
    RICE_FILE_MANAGER="${RICE_FILE_MANAGER:-thunar}" \
    RICE_GDS_PORTAL="${RICE_GDS_PORTAL:-0}" \
    PATH="$HOME_DIR/.local/bin:$BIN:$PATH" \
    bash "$REPO_ROOT/scripts/04n-lowspec-niri.sh" "$@"
}

hash_home() {
    python3 - "$HOME_DIR" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
out = []
for dirpath, _, files in os.walk(root):
    for name in sorted(files):
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, root)
        if rel.startswith(".local/state/"):
            continue
        with open(path, "rb") as fh:
            out.append("%s %s" % (rel, hashlib.sha256(fh.read()).hexdigest()))
print("\n".join(sorted(out)))
PY
}

echo "== 1. apply"
run_04n apply || fail "04n apply 失败"

assert_contains "$HOME_DIR/.config/niri/config.kdl" 'include "rice-colors.kdl"'
[[ "$(grep -cF 'include "rice-colors.kdl"' "$HOME_DIR/.config/niri/config.kdl")" == "1" ]] \
    || fail "include 行重复"
assert_contains "$HOME_DIR/.config/niri/binds.kdl" "rice-merge binds begin"
[[ "$(grep -cF 'rice-merge binds begin' "$HOME_DIR/.config/niri/binds.kdl")" == "1" ]] \
    || fail "binds 块重复"
assert_not_contains "$HOME_DIR/.config/niri/binds.kdl" "low-spec rice"
assert_file "$HOME_DIR/.config/niri/rice-colors.kdl"
assert_contains "$HOME_DIR/.config/waybar/config.jsonc" "$HOME_DIR"
assert_not_contains "$HOME_DIR/.config/waybar/config.jsonc" "/home/yg"
assert_contains "$HOME_DIR/.config/waybar/style.css" "color: #fff"
assert_file "$HOME_DIR/.config/waybar/scripts/theme-selector.sh"
assert_file "$HOME_DIR/.config/waybar/themes/theme-a/style.css"
assert_file "$HOME_DIR/.local/bin/rice-paper"
assert_file "$HOME_DIR/Pictures/_wallpapers/wall.png"
assert_contains "$HOME_DIR/.config/matugen/config.toml" "[templates.foot]"
assert_contains "$HOME_DIR/.config/matugen/config.toml" "[templates.mako]"
assert_contains "$HOME_DIR/.config/matugen/config.toml" "[templates.fuzzel]"
assert_contains "$HOME_DIR/.config/matugen/config.toml" "[templates.waybar]"
assert_contains "$HOME_DIR/.config/matugen/config.toml" "[templates.niri]"
assert_file "$HOME_DIR/.config/environment.d/91-low-spec-fcitx.conf"
assert_file "$HOME_DIR/.config/foot/foot.ini"
assert_file "$HOME_DIR/.config/foot/rice-theme.ini"
assert_file "$HOME_DIR/.config/fuzzel/fuzzel.ini"
assert_file "$HOME_DIR/.config/mako/config"
assert_file "$HOME_DIR/.config/gtk-3.0/gtk.css"
assert_file "$HOME_DIR/.config/gtk-4.0/gtk.css"
assert_file "$HOME_DIR/.config/environment.d/90-wayland-perf.conf"
assert_file "$HOME_DIR/.config/matugen/templates/foot.ini"
assert_file "$HOME_DIR/.config/matugen/templates/mako.conf"
assert_file "$HOME_DIR/.config/matugen/templates/fuzzel.ini"
assert_contains "$HOME_DIR/.config/foot/foot.ini" "JetBrainsMono"
assert_not_contains "$HOME_DIR/.config/niri/config.kdl" "must not be deployed"
assert_contains "$HOME_DIR/.config/niri/config.kdl" 'include "binds.kdl"'
assert_file "$HOME_DIR/.config/waybar/config.jsonc.rice.bak"
assert_file "$HOME_DIR/.config/niri/config.kdl.rice.bak"
assert_file "$HOME_DIR/.local/state/rice-merge/manifest.tsv"
open=$(tr -cd '{' <"$HOME_DIR/.config/niri/binds.kdl" | wc -c | tr -d ' ')
close=$(tr -cd '}' <"$HOME_DIR/.config/niri/binds.kdl" | wc -c | tr -d ' ')
[[ "$open" == "$close" ]] || fail "binds.kdl 花括号不平衡"
ok "合并结果正确"

echo "== 2. 重跑幂等"
before="$(hash_home)"
run_04n apply || fail "04n 第二次 apply 失败"
after="$(hash_home)"
[[ "$before" == "$after" ]] || {
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    fail "第二次运行改变了文件内容"
}
ok "幂等"

echo "== 3. undo"
run_04n undo || fail "04n undo 失败"
[[ "$(cat "$HOME_DIR/.config/waybar/config.jsonc")" == "$ORIGINAL_WAYBAR" ]] \
    || fail "waybar config 未恢复"
assert_not_contains "$HOME_DIR/.config/niri/config.kdl" 'include "rice-colors.kdl"'
assert_not_contains "$HOME_DIR/.config/niri/binds.kdl" "rice-merge binds"
assert_no_file "$HOME_DIR/.config/niri/rice-colors.kdl"
assert_no_file "$HOME_DIR/.config/waybar/config.jsonc.rice.bak"
assert_no_file "$HOME_DIR/.config/niri/config.kdl.rice.bak"
assert_no_file "$HOME_DIR/.config/gtk-3.0/gtk.css"
assert_no_file "$HOME_DIR/.config/gtk-4.0/gtk.css"
assert_no_file "$HOME_DIR/.config/environment.d/90-wayland-perf.conf"
assert_no_file "$HOME_DIR/.config/matugen/templates/foot.ini"
ok "undo 回到初始状态"

echo "== 4. undo 后可重新 apply"
run_04n apply || fail "undo 后重新 apply 失败"
assert_contains "$HOME_DIR/.config/niri/config.kdl" 'include "rice-colors.kdl"'
ok "可重新 apply"

echo "== 5. 契约破坏时 check 失败"
cp "$HOME_DIR/.config/niri/config.kdl" "$TMP/config.saved"
grep -v '^include "layout.kdl"$' "$TMP/config.saved" | grep -v '^include "binds.kdl"$' \
    >"$HOME_DIR/.config/niri/config.kdl"
if run_04n check >/dev/null 2>&1; then
    fail "契约破坏后 check 仍返回成功"
fi
cp "$TMP/config.saved" "$HOME_DIR/.config/niri/config.kdl"
ok "check 会拒绝变化的 shorin 结构"

echo "== 6. GDS Files 注册（跳过包安装）"
RICE_FILE_MANAGER=gds RICE_GDS_PORTAL=1 run_04n apply || fail "04n apply（gds）失败"
assert_contains "$HOME_DIR/.config/mimeapps.list" \
    "inode/directory=io.github.GanDesktop.GdsFiles.desktop"
assert_contains "$HOME_DIR/.config/niri/binds.kdl" 'spawn "gds-files"'
assert_contains "$HOME_DIR/.config/xdg-desktop-portal/niri-portals.conf" \
    "org.freedesktop.impl.portal.FileChooser=gds;"
ok "mimeapps / Mod+E / portal 指向 GDS"

before="$(hash_home)"
RICE_FILE_MANAGER=gds RICE_GDS_PORTAL=1 run_04n apply || fail "04n 第二次 apply（gds）失败"
after="$(hash_home)"
[[ "$before" == "$after" ]] || {
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
    fail "GDS 路径重跑不幂等"
}
ok "GDS 路径幂等"

RICE_FILE_MANAGER=gds RICE_GDS_PORTAL=1 run_04n undo || fail "04n undo（gds）失败"
assert_contains "$HOME_DIR/.config/mimeapps.list" \
    "inode/directory=org.gnome.Nautilus.desktop"
assert_not_contains "$HOME_DIR/.config/niri/binds.kdl" "gds-files"
assert_contains "$HOME_DIR/.config/xdg-desktop-portal/niri-portals.conf" \
    "org.freedesktop.impl.portal.FileChooser=gtk;"
ok "GDS undo 恢复默认文件管理器"

printf '\n全部通过（%d 组）\n' "$pass"
