#!/usr/bin/env bash
# rice-merge 公共 shell 库
#
# 设计目标：
#   1. 04n 可以脱离 shorin 树运行——没有 00-utils.sh 时用这里的回退实现；
#   2. 所有写盘操作登记到 manifest，`04n undo` 能逐条回滚；
#   3. 预检只读，失败发生在写盘之前。
#
# 若 shorin 的 00-utils.sh 已加载，同名函数（log/warn/section/exe/as_user/chown_user）
# 以 shorin 的版本为准：04n 先 source 本文件，再 source 00-utils.sh。

RICE_DRY_RUN="${RICE_DRY_RUN:-0}"

# ----------------------------------------------------------------------------
# 输出（仅在 shorin 未提供时生效）
# ----------------------------------------------------------------------------
if ! declare -F log >/dev/null 2>&1; then
    log() { printf '   -> %s\n' "$*"; }
fi
if ! declare -F warn >/dev/null 2>&1; then
    warn() { printf '   !! %s\n' "$*" >&2; }
fi
if ! declare -F error >/dev/null 2>&1; then
    error() { printf '   xx %s\n' "$*" >&2; }
fi
if ! declare -F success >/dev/null 2>&1; then
    success() { printf '   ok %s\n' "$*"; }
fi
if ! declare -F section >/dev/null 2>&1; then
    section() { printf '\n== %s: %s\n' "$1" "$2"; }
fi
if ! declare -F hr >/dev/null 2>&1; then
    hr() { printf '%s\n' "------------------------------------------------------------"; }
fi
if ! declare -F exe >/dev/null 2>&1; then
    exe() { "$@"; }
fi
if ! declare -F as_user >/dev/null 2>&1; then
    as_user() {
        if [[ "$(id -u)" -eq 0 && -n "${TARGET_USER:-}" ]]; then
            runuser -u "$TARGET_USER" -- "$@"
        else
            "$@"
        fi
    }
fi
if ! declare -F chown_user >/dev/null 2>&1; then
    chown_user() {
        [[ -n "${TARGET_USER:-}" ]] || return 0
        chown -R "$TARGET_USER:" "$1" 2>/dev/null || chown -R "$TARGET_USER" "$1" 2>/dev/null || true
    }
fi

die() {
    printf '\n   [FATAL] %s\n' "$*" >&2
    exit 1
}

# ----------------------------------------------------------------------------
# 身份与状态目录
# ----------------------------------------------------------------------------
rice_resolve_identity() {
    if [[ -n "${RICE_HOME:-}" ]]; then
        HOME_DIR="$RICE_HOME"
        TARGET_USER="${RICE_USER:-$(basename "$HOME_DIR")}"
    elif declare -F detect_target_user >/dev/null 2>&1; then
        detect_target_user
    elif [[ -n "${RICE_USER:-}" ]]; then
        TARGET_USER="$RICE_USER"
        HOME_DIR="/home/$TARGET_USER"
    else
        TARGET_USER="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd)"
        [[ -n "$TARGET_USER" ]] || die "找不到普通用户；请设置 RICE_USER 或 RICE_HOME"
        HOME_DIR="/home/$TARGET_USER"
    fi
    [[ -d "$HOME_DIR" ]] || die "家目录不存在: $HOME_DIR"
    export TARGET_USER HOME_DIR
}

rice_require_root() {
    if [[ "${RICE_ALLOW_NONROOT:-0}" == "1" || "$RICE_DRY_RUN" == "1" ]]; then
        return 0
    fi
    [[ "$(id -u)" -eq 0 ]] || die "需要 root（或设置 RICE_ALLOW_NONROOT=1 用于测试）"
}

rice_init_state() {
    RICE_STATE_DIR="${RICE_STATE_DIR:-$HOME_DIR/.local/state/rice-merge}"
    RICE_MANIFEST="$RICE_STATE_DIR/manifest.tsv"
    [[ "$RICE_DRY_RUN" == "1" ]] && return 0
    mkdir -p "$RICE_STATE_DIR" || die "无法创建状态目录: $RICE_STATE_DIR"
}

# kind \t path \t backup
record_once() {
    local kind="$1" path="$2" backup="${3:-}"
    [[ "$RICE_DRY_RUN" == "1" ]] && return 0
    [[ -f "$RICE_MANIFEST" ]] || : >"$RICE_MANIFEST"
    if awk -F'\t' -v k="$kind" -v p="$path" '$1 == k && $2 == p {found = 1} END {exit !found}' "$RICE_MANIFEST"; then
        return 0
    fi
    printf '%s\t%s\t%s\n' "$kind" "$path" "$backup" >>"$RICE_MANIFEST"
}

rice_backup_once() {
    local path="$1"
    [[ -e "$path" ]] || return 0
    [[ -e "$path.rice.bak" ]] && return 0
    cp -a "$path" "$path.rice.bak" || die "备份失败: $path"
}

# 该路径是否已由本工具写过（重跑时不再把“自己的文件”备份一遍）
rice_was_written() {
    [[ -f "$RICE_MANIFEST" ]] || return 1
    awk -F'\t' -v p="$1" '$1 == "file" && $2 == p {found = 1} END {exit !found}' "$RICE_MANIFEST"
}

rice_mkdir() {
    local dir="$1"
    [[ -d "$dir" ]] && return 0
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] mkdir $dir"
        return 0
    fi
    mkdir -p "$dir" || die "无法创建目录: $dir"
    record_once dir "$dir"
}

# rice_put <src> <dst> [mode]
rice_put() {
    local src="$1" dst="$2" mode="${3:-644}" backup=""
    [[ -f "$src" ]] || die "源文件不存在: $src"
    rice_mkdir "$(dirname "$dst")"
    if [[ -e "$dst" ]]; then
        if ! rice_was_written "$dst"; then
            rice_backup_once "$dst"
            backup="$dst.rice.bak"
        elif [[ -e "$dst.rice.bak" ]]; then
            backup="$dst.rice.bak"
        fi
    fi
    if [[ "$RICE_DRY_RUN" == "1" ]]; then
        log "[dry-run] put $src -> $dst"
        return 0
    fi
    cp -f "$src" "$dst" || die "复制失败: $src -> $dst"
    chmod "$mode" "$dst" || warn "chmod 失败: $dst"
    chown_user "$dst"
    record_once file "$dst" "$backup"
}

# rice_put_tree <src_dir> <dst_dir> [mode]
rice_put_tree() {
    local src="$1" dst="$2" mode="${3:-644}" rel
    [[ -d "$src" ]] || die "源目录不存在: $src"
    while IFS= read -r rel; do
        rice_put "$src/$rel" "$dst/$rel" "$mode"
    done < <(cd "$src" && find . -type f -print | sed 's|^\./||')
}

# 只补缺，不覆盖用户已有文件
rice_put_tree_noclobber() {
    local src="$1" dst="$2" mode="${3:-644}" rel
    [[ -d "$src" ]] || return 0
    while IFS= read -r rel; do
        [[ -e "$dst/$rel" ]] && continue
        rice_put "$src/$rel" "$dst/$rel" "$mode"
    done < <(cd "$src" && find . -type f -print | sed 's|^\./||')
}

rice_undo() {
    [[ -f "$RICE_MANIFEST" ]] || die "没有找到 manifest: $RICE_MANIFEST（没有可回滚的记录）"
    local -a lines=()
    local line kind path backup i
    while IFS= read -r line; do
        lines+=("$line")
    done <"$RICE_MANIFEST"

    log "回滚 ${#lines[@]} 条记录：$RICE_MANIFEST"
    for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
        IFS=$'\t' read -r kind path backup <<<"${lines[$i]}"
        case "$kind" in
            file)
                if [[ -n "$backup" && -e "$backup" ]]; then
                    cp -a "$backup" "$path" && rm -f "$backup"
                    log "restored $path"
                else
                    rm -f "$path"
                    log "removed  $path"
                fi
                ;;
            dir)
                rmdir "$path" 2>/dev/null || true
                ;;
            pkg)
                # 只卸本工具装的包，不动依赖（-R 而不是 -Rns）
                if command -v pacman >/dev/null 2>&1; then
                    if pacman -R --noconfirm "$path" >/dev/null 2>&1; then
                        log "removed  pkg $path"
                    else
                        warn "无法卸载包: $path（可能被其他包依赖）"
                    fi
                else
                    warn "跳过包卸载（没有 pacman）: $path"
                fi
                ;;
        esac
    done
    rm -f "$RICE_MANIFEST"
    success "回滚完成（建议重新登录 niri/waybar）"
}

# ----------------------------------------------------------------------------
# 预检原语：只读，失败即退出
# ----------------------------------------------------------------------------
require_file() {
    [[ -f "$1" ]] || die "缺少文件: $1"
}

require_dir() {
    [[ -d "$1" ]] || die "缺少目录: $1"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"
}

line_exists() {
    [[ -f "$1" ]] || return 1
    awk -v want="$2" '{ gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 == want) found = 1 } END { exit !found }' "$1"
}

require_line() {
    line_exists "$1" "$2" || die "$1 中找不到契约行: $2"
}

# 最后一个非空行必须是 }
last_line_is_brace() {
    [[ -f "$1" ]] || return 1
    local last
    last="$(awk 'NF { line = $0 } END { gsub(/^[ \t]+|[ \t]+$/, "", line); print line }' "$1")"
    [[ "$last" == "}" ]]
}

require_last_brace() {
    last_line_is_brace "$1" || die "$1 的最后一个非空行不是 '}'，binds 插入锚点已失效"
}

braces_balanced() {
    [[ -f "$1" ]] || return 1
    local open close
    open="$(tr -cd '{' <"$1" | wc -c | tr -d ' ')"
    close="$(tr -cd '}' <"$1" | wc -c | tr -d ' ')"
    [[ "$open" == "$close" ]]
}
