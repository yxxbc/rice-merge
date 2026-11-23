#!/bin/bash

export SHELL=$(command -v bash)

# ==============================================================================
# Shorin Arch Setup - Main Installer (v1.2)
#
# Forked from SHORiN-KiWATA/shorin-arch-setup @ e442234 (AGPL-3.0).
# Local changes (see UPSTREAM.md):
#   - --unattended / --desktop / --modules / --skip-reflector flags
#   - desktop menu reduced to Minimal Niri (other DE payloads are not vendored)
#   - minimalniri now runs 04n-lowspec-niri.sh and clones the Low-Spec layer
# ==============================================================================

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# --- Source Visual Engine ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found."
    exit 1
fi

# --- Global Cleanup on Exit ---
cleanup() {
    rm -f "/tmp/shorin_install_user"
}
trap cleanup EXIT

# --- Global Trap (Restore Cursor on Exit) ---
cleanup_on_exit() {
    tput cnorm
}
trap cleanup_on_exit EXIT

# --- Environment ---
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

# --- Fork additions: flags ----------------------------------------------------
UNATTENDED="${UNATTENDED:-0}"
SKIP_REFLECTOR="${SKIP_REFLECTOR:-0}"
MODULES_CSV="${MODULES_CSV:-}"
RICE_FILE_MANAGER="${RICE_FILE_MANAGER:-}"
RICE_GDS_PORTAL="${RICE_GDS_PORTAL:-0}"

usage() {
    cat <<EOF
用法: sudo bash install.sh [选项]
  --unattended        非交互：Minimal Niri + 必须模块
  --desktop NAME      minimalniri | none
  --modules a,b       额外模块（如 01b-shorin-arch.sh）
  --file-manager NAME thunar（默认）| gds | gds-portal（GDS Files + 文件选择器）
  --gds-portal        等同 --file-manager gds-portal
  --skip-reflector    跳过镜像刷新
  --no-reboot         结束时不重启（live/chroot 用）
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unattended) UNATTENDED=1; shift ;;
        --desktop) DESKTOP_ENV="$2"; shift 2 ;;
        --desktop=*) DESKTOP_ENV="${1#*=}"; shift ;;
        --modules) MODULES_CSV="$2"; shift 2 ;;
        --modules=*) MODULES_CSV="${1#*=}"; shift ;;
        --file-manager) RICE_FILE_MANAGER="$2"; shift 2 ;;
        --file-manager=*) RICE_FILE_MANAGER="${1#*=}"; shift ;;
        --gds-portal) RICE_GDS_PORTAL=1; shift ;;
        --skip-reflector) SKIP_REFLECTOR=1; shift ;;
        --no-reboot) NO_REBOOT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage; exit 2 ;;
    esac
done
export UNATTENDED SKIP_REFLECTOR MODULES_CSV NO_REBOOT
if [[ -n "${DESKTOP_ENV:-}" && "$DESKTOP_ENV" != "minimalniri" && "$DESKTOP_ENV" != "none" ]]; then
    echo "此 fork 只打包了 Minimal Niri 的 dotfiles；--desktop 仅支持 minimalniri / none" >&2
    exit 2
fi

case "${RICE_FILE_MANAGER:-thunar}" in
    thunar) ;;
    gds) ;;
    gds-portal) RICE_FILE_MANAGER=gds; RICE_GDS_PORTAL=1 ;;
    *) echo "--file-manager 仅支持 thunar / gds / gds-portal" >&2; exit 2 ;;
esac
if [[ "$RICE_GDS_PORTAL" == "1" && "${RICE_FILE_MANAGER:-}" == "thunar" ]]; then
    echo "--gds-portal 需要 GDS Files（--file-manager gds）" >&2
    exit 2
fi
if [[ "$RICE_GDS_PORTAL" == "1" && -z "${RICE_FILE_MANAGER:-}" ]]; then
    RICE_FILE_MANAGER=gds
fi

check_root
chmod +x "$SCRIPTS_DIR"/*.sh

# --- ASCII Banners ---
banner1() {
cat << "EOF"
  ██████  ██   ██  ██████  ███████ ██ ███    ██
  ██      ██   ██ ██    ██ ██   ██   ██ ██  ██
  ███████ ███████ ██    ██ ██████  ██ ██ ██  ██
       ██ ██   ██ ██    ██ ██   ██ ██ ██  ██ ██
  ██████  ██   ██  ██████  ██   ██ ██ ██   ████
EOF
}

export SHORIN_BANNER_IDX=0

show_banner() {
    clear
    echo -e "${H_CYAN}"
    case $SHORIN_BANNER_IDX in
        0) banner1 ;;
    esac
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation ::${NC}"
    echo -e ""
}

# --- Desktop Selection Menu (FZF Powered) ---
select_desktop() {
    if [[ -n "${DESKTOP_ENV:-}" ]]; then
        log "Selected (preset): ${DESKTOP_ENV}"
        return 0
    fi
    if [[ "$UNATTENDED" == "1" ]]; then
        DESKTOP_ENV="minimalniri"
        export DESKTOP_ENV
        log "unattended: defaulting to minimalniri"
        return 0
    fi

    if ! command -v fzf &> /dev/null; then
        echo -e "   ${DIM}Installing fzf for interactive menu...${NC}"
        pacman -S --noconfirm --needed fzf >/dev/null 2>&1
    fi
    
    local MENU_ITEMS=(
        "Minimal_Niri + rice-merge ${H_YELLOW}(Recommended)${NC}|minimalniri"
        "No_Desktop|none"
    )
    
    while true; do
        show_banner
        
        local fzf_list=()
        local idx=1
        for item in "${MENU_ITEMS[@]}"; do
            [[ -z "$item" ]] && continue
            
            local name="${item%%|*}"
            local val="${item##*|}"
            local colored_idx="${H_CYAN}[${idx}]${NC}"
            
            if [ $idx -lt 10 ]; then
                fzf_list+=("${colored_idx}   ${name}\t${val}\t${name}")
            else
                fzf_list+=("${colored_idx}  ${name}\t${val}\t${name}")
            fi
            ((idx++))
        done
        
        local selected
        selected=$(printf "%b\n" "${fzf_list[@]}" | sed '/^[[:space:]]*$/d' | fzf \
            --ansi \
            --delimiter='\t' \
            --with-nth=1 \
            --info=hidden \
            --layout=reverse \
            --border="rounded" \
            --border-label="  Select Desktop Environment  " \
            --border-label-pos=5 \
            --color="marker:cyan,pointer:cyan,label:yellow" \
            --header=" [J/K] Select | [Enter] confirm" \
            --pointer=">" \
            --bind 'j:down,k:up,ctrl-c:abort,esc:abort' \
        --height=~20)
        
        local fzf_status=$?
        
        if [ $fzf_status -eq 130 ]; then
            echo -e "\n   ${H_RED}>>> Installation aborted by user.${NC}"
            exit 130
        fi
        
        if [ -z "$selected" ]; then continue; fi
        
        export DESKTOP_ENV="$(echo "$selected" | awk -F'\t' '{print $2}')"
        local selected_name="$(echo "$selected" | awk -F'\t' '{print $3}')"
        
        if [ "$DESKTOP_ENV" == "random" ]; then
            local POOL=()
            for item in "${MENU_ITEMS[@]}"; do
                [[ -z "$item" ]] && continue
                local oid="${item##*|}"
                if [[ "$oid" != "none" && "$oid" != "random" ]]; then
                    POOL+=("$item")
                fi
            done
            
            local rand_idx=$(( RANDOM % ${#POOL[@]} ))
            local final_item="${POOL[$rand_idx]}"
            local final_name="${final_item%%|*}"
            export DESKTOP_ENV="${final_item##*|}"
            
            echo -e "\n   ${H_CYAN}>>> Randomly selected:${NC} ${BOLD}${final_name}${NC}"
            read -p "$(echo -e "   ${H_YELLOW}Continue with this selection? [Y/n]: ${NC}")" confirm
            
            if [[ "${confirm,,}" == "n" ]]; then continue; else break; fi
        else
            log "Selected: ${selected_name}"
            sleep 0.5
            break
        fi
    done
}

# --- File Manager Selection (Minimal Niri only) ---
select_file_manager() {
    if [[ -n "${RICE_FILE_MANAGER:-}" ]]; then
        log "Selected file manager (preset): ${RICE_FILE_MANAGER} (portal=${RICE_GDS_PORTAL})"
        export RICE_FILE_MANAGER RICE_GDS_PORTAL
        return 0
    fi

    if [[ "$DESKTOP_ENV" != "minimalniri" ]]; then
        RICE_FILE_MANAGER=thunar
        RICE_GDS_PORTAL=0
        export RICE_FILE_MANAGER RICE_GDS_PORTAL
        return 0
    fi

    if [[ "$UNATTENDED" == "1" || ! -t 0 ]]; then
        RICE_FILE_MANAGER=thunar
        RICE_GDS_PORTAL=0
        export RICE_FILE_MANAGER RICE_GDS_PORTAL
        log "unattended: file manager defaults to thunar"
        return 0
    fi

    local MENU_ITEMS=(
        "Thunar ${H_YELLOW}(default, GTK)${NC}|thunar|0"
        "GDS Files ${H_YELLOW}(experimental, Rust/GPUI)${NC}|gds|0"
        "GDS Files + GDS Portal ${H_YELLOW}(experimental, file chooser too)${NC}|gds|1"
    )
    local fzf_list=() item name rest
    for item in "${MENU_ITEMS[@]}"; do
        name="${item%%|*}"
        rest="${item#*|}"
        fzf_list+=("${name}\t${rest}")
    done

    local selected="" val="" portal="0" rc=0
    if ! command -v fzf &>/dev/null; then
        pacman -S --noconfirm --needed fzf >/dev/null 2>&1 || true
    fi

    if command -v fzf &>/dev/null; then
        selected=$(printf "%b\n" "${fzf_list[@]}" | fzf \
            --ansi \
            --delimiter='\t' \
            --with-nth=1 \
            --info=hidden \
            --layout=reverse \
            --border="rounded" \
            --border-label="  File Manager  " \
            --border-label-pos=5 \
            --color="marker:cyan,pointer:cyan,label:yellow" \
            --header=" [J/K] Select | [Enter] confirm " \
            --pointer=">" \
            --bind 'j:down,k:up,ctrl-c:abort,esc:abort' \
            --height=~20)
        rc=$?
        if [ $rc -eq 130 ]; then
            echo -e "\n   ${H_RED}>>> Installation aborted by user.${NC}"
            exit 130
        fi
        if [ -n "$selected" ]; then
            rest=$(awk -F'\t' '{print $2}' <<<"$selected")
            val="${rest%%|*}"
            portal="${rest##*|}"
        fi
    else
        echo "" >&2
        echo -e "   ${BOLD}File manager / 文件管理器${NC}" >&2
        local i=1
        for item in "${MENU_ITEMS[@]}"; do
            echo -e "     ${i}) ${item%%|*}" >&2
            ((i++))
        done
        local pick
        read -r -p "   Select [1-3, Enter=1]: " pick || pick=1
        pick="${pick:-1}"
        case "$pick" in
            1) val=thunar; portal=0 ;;
            2) val=gds; portal=0 ;;
            3) val=gds; portal=1 ;;
            *) val=thunar; portal=0 ;;
        esac
    fi

    RICE_FILE_MANAGER="${val:-thunar}"
    RICE_GDS_PORTAL="${portal:-0}"
    export RICE_FILE_MANAGER RICE_GDS_PORTAL
    log "Selected file manager: ${RICE_FILE_MANAGER} (portal=${RICE_GDS_PORTAL})"
    if [[ "$RICE_FILE_MANAGER" == "gds" ]]; then
        warn "GDS Files 仍处于早期版本；matugen 取色不会作用于 GDS 窗口"
    fi
    sleep 0.5
}

# --- Optional Modules Selection Menu (FZF Powered) ---
select_optional_modules() {
    if [[ "$UNATTENDED" == "1" ]]; then
        OPTIONAL_MODULES=()
        if [[ -n "$MODULES_CSV" ]]; then
            IFS=',' read -r -a OPTIONAL_MODULES <<<"$MODULES_CSV"
        fi
        log "unattended: optional modules = ${OPTIONAL_MODULES[*]:-none}"
        return 0
    fi

    local OPTIONAL_MENU=(
        "Shorin Arch Repository|01b-shorin-arch.sh"
        "IWD WiFi Backend|01c-nm-backend.sh"
        "Windows Linux Dualboot Setup|02c-dualboot-fix.sh"
        "Hardware Drivers|03b-gpu-driver.sh"
        "Grub Themes|07-grub-theme.sh"
        "Common Apps|99-apps.sh"
    )
    
    show_banner
    
    local fzf_list=()
    for item in "${OPTIONAL_MENU[@]}"; do
        local name="${item%%|*}"
        local val="${item##*|}"
        fzf_list+=("  ${name}\t${val}")
    done
    
    # 核心修复：引入 --expect=ctrl-x,enter 来拦截按键动作
    local selected_raw
    selected_raw=$(printf "%b\n" "${fzf_list[@]}" | fzf \
        --multi \
        --delimiter='\t' \
        --with-nth=1 \
        --layout=reverse \
        --border="rounded" \
        --border-label="  Select Optional Modules  " \
        --border-label-pos=5 \
        --color="marker:cyan,pointer:cyan,label:yellow" \
        --header=" [TAB]: Toggle | [CTRL-X]: Skip All | [ENTER]: Confirm " \
        --pointer=">" \
        --expect=ctrl-x,enter \
        --bind 'start:select-all,ctrl-a:select-all,ctrl-d:deselect-all,ctrl-c:abort,esc:abort,j:down,k:up' \
    --height=~20)
    
    local fzf_status=$?
    if [ $fzf_status -eq 130 ]; then
        echo -e "\n   ${H_RED}>>> Installation aborted by user.${NC}"
        exit 130
    fi
    
    OPTIONAL_MODULES=()
    
    if [ -n "$selected_raw" ]; then
        # 解析 FZF 输出：第一行是按下的键，后面是选中的内容
        local key
        key=$(head -n 1 <<< "$selected_raw")
        local selected_items
        selected_items=$(sed '1d' <<< "$selected_raw")

        # 完美解决“回车默认选中光标项”的问题：用户直接按 Ctrl-X 即可退出并清空
        if [[ "$key" == "ctrl-x" ]]; then
            log "Skipping all optional modules..."
            sleep 0.5
        else
            if [ -n "$selected_items" ]; then
                # 利用 awk 过滤掉空行，防止产生空元素
                mapfile -t OPTIONAL_MODULES < <(echo "$selected_items" | awk -F'\t' '{if ($2 != "") print $2}')
            fi
        fi
    fi
}

sys_dashboard() {
    echo -e "${H_BLUE}╔════ SYSTEM DIAGNOSTICS ══════════════════════════════╗${NC}"
    echo -e "${H_BLUE}║${NC} ${BOLD}Kernel${NC}   : $(uname -r)"
    echo -e "${H_BLUE}║${NC} ${BOLD}User${NC}     : $(whoami)"
    echo -e "${H_BLUE}║${NC} ${BOLD}Desktop${NC}  : ${H_CYAN}${DESKTOP_ENV^^}${NC}"
    if [[ "$DESKTOP_ENV" == "minimalniri" ]]; then
        local fm_label="${RICE_FILE_MANAGER:-thunar}"
        [[ "${RICE_GDS_PORTAL:-0}" == "1" ]] && fm_label+=" + portal"
        echo -e "${H_BLUE}║${NC} ${BOLD}Filemgr${NC}  : ${H_CYAN}${fm_label}${NC}"
    fi
    echo -e "${H_BLUE}║${NC} ${BOLD}Modules${NC}  : ${#OPTIONAL_MODULES[@]} optional module(s) selected"
    
    if [ "$CN_MIRROR" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_YELLOW}CN Optimized (Manual)${NC}"
    elif [ "$DEBUG" == "1" ]; then
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : ${H_RED}DEBUG FORCE (CN Mode)${NC}"
    else
        echo -e "${H_BLUE}║${NC} ${BOLD}Network${NC}  : Global Default"
    fi
    
    if [ -f "$STATE_FILE" ]; then
        done_count=$(wc -l < "$STATE_FILE")
        echo -e "${H_BLUE}║${NC} ${BOLD}Progress${NC} : Resuming ($done_count steps recorded)"
    fi
    echo -e "${H_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# --- Main Execution ---

if [ ! -f "$STATE_FILE" ]; then touch "$STATE_FILE"; fi

migrate_progress_entry() {
    local old_name="$1"
    local new_name="$2"

    if grep -q "^${old_name}$" "$STATE_FILE"; then
        sed -i "s/^${old_name}$/${new_name}/" "$STATE_FILE"
    fi
}

migrate_progress_entry "01b-nm-backend.sh" "01c-nm-backend.sh"
migrate_progress_entry "01c-shorin-arch.sh" "01b-shorin-arch.sh"
migrate_progress_entry "02a-dualboot-fix.sh" "02c-dualboot-fix.sh"
migrate_progress_entry "02-musthave.sh" "02b-musthave.sh"
migrate_progress_entry "03a-user.sh" "02a-user.sh"

log "Initializing installer sequence..."
sleep 0.5

select_desktop
select_file_manager
select_optional_modules
clear
show_banner
sys_dashboard

MANDATORY_MODULES=(
    "00-btrfs-init.sh"
    "01a-base.sh"
    "02a-user.sh"
    "02b-musthave.sh"
    "03c-snapshot-before-desktop.sh"
    "05-verify-desktop.sh"
)

ALL_MODULES=("${MANDATORY_MODULES[@]}" "${OPTIONAL_MODULES[@]}")

case "$DESKTOP_ENV" in
    shorinniri)    ALL_MODULES+=("04-niri-setup.sh") ;;
    minimalniri)   ALL_MODULES+=("04j-minimal-niri.sh" "04n-lowspec-niri.sh") ;;
    kde)           ALL_MODULES+=("04b-kdeplasma-setup.sh") ;;
    end4)          ALL_MODULES+=("04e-illogical-impulse-end4-quickshell.sh") ;;
    dms)           ALL_MODULES+=("04c-dms-quickshell.sh") ;;
    inir)          ALL_MODULES+=("04m-inir-quickshell.sh") ;;
    shorindmsgit)  ALL_MODULES+=("04h-shorindms-quickshell.sh"); export SHORIN_DMS_GIT=1 ;;
    hyprniri)      ALL_MODULES+=("04i-shorin-hyprniri-quickshell.sh") ;;
    shorinnocniri) ALL_MODULES+=("04k-shorin-noctalia-quickshell.sh") ;;
    caelestia)     ALL_MODULES+=("04g-caelestia-quickshell.sh") ;;
    gnome)         ALL_MODULES+=("04d-gnome.sh") ;;
    minimallabwc)  ALL_MODULES+=("04l-minimal-labwc.sh") ;;
    none)          log "Skipping Desktop Environment installation." ;;
    *)             warn "Unknown selection, skipping desktop setup." ;;
esac

mapfile -t MODULES < <(printf "%s\n" "${ALL_MODULES[@]}" | sort -u)

TOTAL_STEPS=${#MODULES[@]}
CURRENT_STEP=0

# --- Reflector Mirror Update (State Aware) ---
section "Pre-Flight" "Mirrorlist Optimization"

if [[ "$UNATTENDED" == "1" || "$SKIP_REFLECTOR" == "1" ]]; then
    log "Skipping reflector (unattended/skip-reflector)."
elif grep -q "^REFLECTOR_DONE$" "$STATE_FILE"; then
    echo -e "   ${H_GREEN}✔${NC} Mirrorlist previously optimized."
    echo -e "   ${DIM}   Skipping Reflector steps (Resume Mode)...${NC}"
else
    CURRENT_TZ=$(readlink -f /etc/localtime)
    REFLECTOR_ARGS="--protocol https -a 12 -f 10 --sort rate --save /etc/pacman.d/mirrorlist --verbose"
    
    REFLECTOR_SUCCESS=0
    if [[ "$CURRENT_TZ" == *"Shanghai"* ]]; then
        echo ""
        echo -e "${H_YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${H_YELLOW}║  DETECTED TIMEZONE: Asia/Shanghai                                ║${NC}"
        echo -e "${H_YELLOW}║  Refreshing mirrors in China can be slow.                        ║${NC}"
        echo -e "${H_YELLOW}║  Do you want to force refresh mirrors with Reflector?            ║${NC}"
        echo -e "${H_YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector?[y/N] (Default No in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-N}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            log "Checking Reflector..."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Running Reflector for China..."
                if exe reflector $REFLECTOR_ARGS -c China; then
                    success "Mirrors updated."
                    REFLECTOR_SUCCESS=1
                else
                    warn "China mirror refresh failed. Trying latest 30 global mirrors..."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Continuing with existing mirrors."
                    fi
                fi
            else
                warn "Could not install Reflector. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    else
        echo ""
        echo -e "${H_CYAN}Mirror refresh with Reflector is recommended outside China.${NC}"
        read -t 60 -p "$(echo -e "   ${H_CYAN}Run Reflector?[Y/n] (Default Yes in 60s): ${NC}")" choice
        if [ $? -ne 0 ]; then echo ""; fi
        choice=${choice:-Y}
        
        if [[ ! "$choice" =~ ^[Nn]$ ]]; then
            log "Checking Reflector..."
            if exe pacman -S --noconfirm --needed reflector; then
                log "Detecting location for optimization..."
                COUNTRY_CODE=$(curl -s --max-time 2 https://ipinfo.io/country)
                
                if [ -n "$COUNTRY_CODE" ]; then
                    info_kv "Country" "$COUNTRY_CODE" "(Auto-detected)"
                    log "Running Reflector for $COUNTRY_CODE..."
                    if exe reflector $REFLECTOR_ARGS -c "$COUNTRY_CODE"; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Country specific refresh failed. Trying latest 30 global mirrors..."
                        if exe reflector $REFLECTOR_ARGS --latest 30; then
                            success "Mirrors updated."
                            REFLECTOR_SUCCESS=1
                        else
                            warn "Reflector failed. Continuing with existing mirrors."
                        fi
                    fi
                else
                    warn "Could not detect country. Trying latest 30 global mirrors..."
                    if exe reflector $REFLECTOR_ARGS --latest 30; then
                        success "Mirrors updated."
                        REFLECTOR_SUCCESS=1
                    else
                        warn "Reflector failed. Continuing with existing mirrors."
                    fi
                fi
            else
                warn "Could not install Reflector. Continuing with existing mirrors."
            fi
        else
            log "Skipping mirror refresh."
        fi
    fi
    
    if [ "$REFLECTOR_SUCCESS" -eq 1 ]; then
        echo "REFLECTOR_DONE" >> "$STATE_FILE"
    fi
fi

# ---- update keyring-----
section "Pre-Flight" "Update Keyring"

exe pacman -Sy --noconfirm archlinux-keyring
exe pacman -Su --noconfirm


# --- Global Update ---
section "Pre-Flight" "System update"
log "Ensuring system is up-to-date..."

if exe pacman -Syyu --noconfirm; then
    success "System Updated."
else
    error "System update failed. Check your network."
    exit 1
fi

# --- Visual layer (Low-Spec) ---------------------------------------------------
# 上游仓库没有 LICENSE，不能 vendor：在这里按需克隆到本地。
if [[ "$DESKTOP_ENV" == "minimalniri" && ! -d "$BASE_DIR/low-spec-dotfiles" ]]; then
    section "Pre-Flight" "Low-Spec Visual Layer"
    exe pacman -S --noconfirm --needed git
    if exe git clone --depth=1 https://github.com/okyashgajjar/Low-Spec-Niri-Dotfiles.git \
        "$BASE_DIR/low-spec-dotfiles"; then
        success "Low-Spec layer cloned."
    else
        error "Low-Spec clone failed: 04n needs $BASE_DIR/low-spec-dotfiles"
        exit 1
    fi
fi

# --- Module Loop ---
for module in "${MODULES[@]}"; do
    [[ -z "$module" ]] && continue
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
    script_path="$SCRIPTS_DIR/$module"
    
    if [ ! -f "$script_path" ]; then
        error "Module not found: $module"
        continue
    fi
    
    if grep -q "^${module}$" "$STATE_FILE"; then
        echo -e "   ${H_GREEN}✔${NC} Module ${BOLD}${module}${NC} already completed."
        echo -e "   ${DIM}   Skipping... (Delete .install_progress to force run)${NC}"
        continue
    fi
    
    section "Module ${CURRENT_STEP}/${TOTAL_STEPS}" "$module"
    
    bash "$script_path"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "$module" >> "$STATE_FILE"
        success "Module $module completed."
    elif [ $exit_code -eq 130 ]; then
        echo ""
        warn "Script interrupted by user (Ctrl+C)."
        log "Exiting without rollback. You can resume later."
        exit 130
    else
        write_log "FATAL" "Module $module failed with exit code $exit_code"
        error "Module execution failed."
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# Final Cleanup
# ------------------------------------------------------------------------------
section "Completion" "System Cleanup"

clean_intermediate_snapshots() {
    local config_name="$1"
    local start_marker="Before Shorin Setup"
    
    local KEEP_MARKERS=(
        "Before Desktop Environments"
        "Before Niri Setup"
    )
    
    if ! snapper -c "$config_name" list &>/dev/null; then
        return
    fi
    
    log "Scanning junk snapshots in: $config_name..."
    
    local start_id
    start_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$start_marker" | awk '{print $1}' | tail -n 1)
    
    if [ -z "$start_id" ]; then
        warn "Marker '$start_marker' not found in '$config_name'. Skipping cleanup."
        return
    fi
    
    local IDS_TO_KEEP=()
    for marker in "${KEEP_MARKERS[@]}"; do
        local found_id
        found_id=$(snapper -c "$config_name" list --columns number,description | grep -F "$marker" | awk '{print $1}' | tail -n 1)
        
        if [ -n "$found_id" ]; then
            IDS_TO_KEEP+=("$found_id")
            log "Found protected snapshot: '$marker' (ID: $found_id)"
        fi
    done
    
    local snapshots_to_delete=()
    
    while IFS= read -r line; do
        local id
        local type
        
        id=$(echo "$line" | awk '{print $1}')
        type=$(echo "$line" | awk '{print $3}')
        
        if [[ "$id" =~ ^[0-9]+$ ]]; then
            if [ "$id" -gt "$start_id" ]; then
                
                local skip=false
                for keep in "${IDS_TO_KEEP[@]}"; do
                    if [[ "$id" == "$keep" ]]; then
                        skip=true
                        break
                    fi
                done
                
                if [ "$skip" = true ]; then
                    continue
                fi
                
                if [[ "$type" == "pre" || "$type" == "post" ]]; then
                    snapshots_to_delete+=("$id")
                fi
            fi
        fi
    done < <(snapper -c "$config_name" list --columns number,type)
    
    if [ ${#snapshots_to_delete[@]} -gt 0 ]; then
        log "Deleting ${#snapshots_to_delete[@]} junk snapshots in '$config_name'..."
        if exe snapper -c "$config_name" delete "${snapshots_to_delete[@]}"; then
            success "Cleaned $config_name."
        fi
    else
        log "No junk snapshots found in '$config_name'."
    fi
}

log "Cleaning Pacman/Yay cache..."
exe pacman -Sc --noconfirm

clean_intermediate_snapshots "root"
clean_intermediate_snapshots "home"

detect_target_user

for dir in /var/cache/pacman/pkg/download-*/; do
    if [ -d "$dir" ]; then
        echo "Found residual directory: $dir, cleaning up..."
        rm -rf "$dir"
    fi
done

VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

log "Regenerating final GRUB configuration..."
exe env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg

# --- Completion ---
clear
show_banner
echo -e "${H_GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${H_GREEN}║               INSTALLATION  COMPLETE                 ║${NC}"
echo -e "${H_GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$STATE_FILE" ]; then rm "$STATE_FILE"; fi

log "Archiving log..."
if [ -f "/tmp/shorin_install_user" ]; then
    FINAL_USER=$(cat /tmp/shorin_install_user)
else
    FINAL_USER=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
fi

if [ -n "$FINAL_USER" ]; then
    FINAL_DOCS="/home/$FINAL_USER/Documents"
    mkdir -p "$FINAL_DOCS"
    if [ -f "${TEMP_LOG_FILE:-/tmp/shorin.log}" ]; then
        cp "${TEMP_LOG_FILE:-/tmp/shorin.log}" "$FINAL_DOCS/log-shorin-arch-setup.txt"
        chown -R "$FINAL_USER:$FINAL_USER" "$FINAL_DOCS"
        echo -e "   ${H_BLUE}●${NC} Log Saved     : ${BOLD}$FINAL_DOCS/log-shorin-arch-setup.txt${NC}"
    fi
fi

echo ""
echo -e "${H_YELLOW}>>> System requires a REBOOT.${NC}"

if [[ "${NO_REBOOT:-0}" == "1" ]]; then
    echo -e "   ${DIM}--no-reboot: 不自动重启（live 安装器稍后处理）${NC}"
    exit 0
fi

while read -r -t 0; do read -r; done

for i in {10..1}; do
    echo -ne "\r   ${DIM}Auto-rebooting in ${i}s... (Press 'n' to cancel)${NC}"
    
    read -t 1 -n 1 input
    if [ $? -eq 0 ]; then
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo -e "\n\n   ${H_BLUE}>>> Reboot cancelled.${NC}"
            exit 0
        else
            break
        fi
    fi
done

echo -e "\n\n   ${H_GREEN}>>> Rebooting...${NC}"
systemctl reboot
