#!/usr/bin/env bash
# Shared helpers for the live installer: logging / dry-run / command execution.
#
# Messages are English on purpose: the Arch live console has no CJK glyphs, so
# Chinese output would show up as boxes. Chinese docs live in README.md instead.

DRY_RUN="${DRY_RUN:-0}"
LOG_FILE="${LOG_FILE:-/tmp/rice-live.log}"
MNT="${MNT:-/mnt}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
: >>"$LOG_FILE" 2>/dev/null || true

say() { printf '%s\n' "$*" | tee -a "$LOG_FILE"; }
step() { printf '\n==> %s\n' "$*" | tee -a "$LOG_FILE"; }
warn() { printf '   !! %s\n' "$*" | tee -a "$LOG_FILE" >&2; }
die() {
    printf '\n[FATAL] %s\n' "$*" | tee -a "$LOG_FILE" >&2
    printf 'Log: %s\n' "$LOG_FILE" >&2
    exit 1
}

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '   [dry-run] %s\n' "$*" | tee -a "$LOG_FILE"
        return 0
    fi
    printf '   + %s\n' "$*" >>"$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

run_sh() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '   [dry-run] sh -c %s\n' "$cmd" | tee -a "$LOG_FILE"
        return 0
    fi
    printf '   + sh -c %s\n' "$cmd" >>"$LOG_FILE"
    bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# Only fill variables that are not already set: environment wins over the file.
load_env_file() {
    local file="$1" key value current
    [[ -f "$file" ]] || die "Config file not found: $file"
    while IFS='=' read -r key value; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        key="$(printf '%s' "$key" | tr -d '[:space:]')"
        [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "Invalid config key: $key"
        eval "current=\${$key+x}"
        [[ -n "$current" ]] && continue
        value="${value%$'\r'}"
        # Strip inline comments ("VALUE   # note") and trailing spaces.
        value="${value%%[[:space:]]#*}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"
        printf -v "$key" '%s' "$value"
        export "$key"
    done <"$file"
}
