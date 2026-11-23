#!/usr/bin/env bash
# 50 — 在新系统里跑模块
#
#   full  : install.sh --unattended --desktop minimalniri（00~05 + 04j + 04n）
#   smoke : 只铺 dotfiles + 04n（跳过所有包安装，验证合并逻辑）
#   base  : install.sh --unattended --desktop none（只跑基础模块）

step_modules() {
    step "50 modules: profile=$PROFILE file-manager=${FILE_MANAGER:-thunar}"
    local script="$MNT/root/rice-modules.sh"
    local fm="${FILE_MANAGER:-thunar}" fm_name fm_portal fm_args
    case "$fm" in
        thunar)    fm_name=thunar; fm_portal=0 ;;
        gds)       fm_name=gds;    fm_portal=0 ;;
        gds-portal) fm_name=gds;   fm_portal=1 ;;
        *) die "FILE_MANAGER must be thunar|gds|gds-portal (got: $fm)" ;;
    esac
    fm_args="--file-manager $fm_name"
    [[ "$fm_portal" == "1" ]] && fm_args+=" --gds-portal"

    if [[ "$DRY_RUN" == "1" ]]; then
        run arch-chroot "$MNT" /bin/bash "/root/rice-modules.sh"
        return 0
    fi

    {
        cat <<EOF
#!/bin/bash
set -uo pipefail
export SHELL=/bin/bash
export LANG=en_US.UTF-8
echo "${USERNAME}" > /tmp/shorin_install_user
# 02a-user.sh 会删掉缓存再重新探测；显式给 TARGET_USER 让它不再提示
export TARGET_USER="${USERNAME}"
export HOME_DIR="/home/${USERNAME}"
export RICE_SKIP_DM=1
EOF
        if [[ -n "${http_proxy:-}${https_proxy:-}" ]]; then
            cat <<EOF
export http_proxy="${http_proxy:-}"
export https_proxy="${https_proxy:-${http_proxy:-}}"
export no_proxy="${no_proxy:-}"
EOF
        fi
        cat <<EOF
export RICE_FILE_MANAGER=${fm_name}
export RICE_GDS_PORTAL=${fm_portal}
cd /opt/setup/rice || exit 1

run_module() {
    echo
    echo "##### module: \$1"
    bash "scripts/\$1" || { echo "[FATAL] module \$1 failed"; exit 1; }
}
EOF

        if [[ "$PROFILE" == "smoke" ]]; then
            cat <<EOF
echo "== smoke: deploying minimal dotfiles"
cp -a minimal-niri-dotfiles/. "/home/${USERNAME}/"
chown -R "${USERNAME}:" "/home/${USERNAME}"
touch "/home/${USERNAME}/.config/niri/output.kdl"
chown "${USERNAME}:" "/home/${USERNAME}/.config/niri/output.kdl"
export RICE_SKIP_PACKAGES=1
run_module 04n-lowspec-niri.sh
EOF
        elif [[ "$PROFILE" == "base" ]]; then
            cat <<'EOF'
bash install.sh --unattended --desktop none --skip-reflector --no-reboot || exit 1
EOF
        else
            cat <<EOF
bash install.sh --unattended --desktop minimalniri --skip-reflector --no-reboot ${fm_args} || exit 1
EOF
        fi

        cat <<EOF

DOCS="/home/${USERNAME}/Documents"
mkdir -p "\$DOCS"
for f in /tmp/log-shorin-arch-setup.txt /tmp/rice-live.log; do
    [ -f "\$f" ] && cp "\$f" "\$DOCS/" 2>/dev/null
done
chown -R "${USERNAME}:" "\$DOCS" 2>/dev/null || true
echo "== modules done"
EOF
    } >"$script"
    chmod +x "$script"

    run arch-chroot "$MNT" /bin/bash /root/rice-modules.sh || die "Modules failed; see /root/rice-modules.sh (kept) and the log"
    rm -f "$script"

    # live 安装器自己的日志在宿主机 /tmp，不在 chroot 里
    run mkdir -p "$MNT/home/$USERNAME/Documents"
    run cp -f "$LOG_FILE" "$MNT/home/$USERNAME/Documents/rice-live.log"
    run_sh "chown -R '$USERNAME:' '$MNT/home/$USERNAME/Documents' 2>/dev/null || true"
}
