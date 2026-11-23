#!/usr/bin/env bash
# 本地 QEMU 验证环境：Arch ISO + 空磁盘 + 9p 共享本仓库
#
# 用法：
#   brew install qemu
#   bash vm/run.sh [/path/to/archlinux.iso]
#
# 环境变量：ARCH_ISO / VM_DISK / VM_MEM / VM_CPUS / VM_SSH_PORT
#
# 进入 live ISO 后：
#   mkdir -p /repo
#   mount -t 9p -o trans=virtio,version=9p2000.L repo /repo
#   bash /repo/vm/live-autoinstall.sh smoke   # 快速验证合并，没有桌面
#   bash /repo/vm/live-autoinstall.sh full    # 真装到 niri 桌面（TCG 很慢）
#
# 完整交互步骤见 vm/WALKTHROUGH.md

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$REPO_ROOT/vm"
mkdir -p "$VM_DIR"

QEMU="${QEMU_BIN:-qemu-system-x86_64}"
command -v "$QEMU" >/dev/null 2>&1 || {
    echo "缺少 $QEMU。macOS: brew install qemu" >&2
    exit 1
}

ISO="${1:-${ARCH_ISO:-}}"
if [[ -z "$ISO" ]]; then
    ISO="$(ls -t "$HOME/Downloads"/archlinux-*.iso 2>/dev/null | head -1 || true)"
fi
[[ -n "$ISO" && -f "$ISO" ]] || {
    echo "找不到 Arch ISO：下载 https://archlinux.org/download/ 后放进 ~/Downloads，或用 ARCH_ISO=/path 指定" >&2
    exit 1
}

DISK="${VM_DISK:-$VM_DIR/arch-test.qcow2}"
MEM="${VM_MEM:-4096}"
CPUS="${VM_CPUS:-4}"
PORT="${VM_SSH_PORT:-2222}"
VM_DISPLAY="${VM_DISPLAY:-cocoa,zoom-to-fit=on}"
VARS="$VM_DIR/edk2-vars.fd"
QMP="$VM_DIR/qmp.sock"

if [[ ! -f "$DISK" ]]; then
    echo "创建磁盘 $DISK (40G)"
    qemu-img create -f qcow2 "$DISK" 40G >/dev/null
fi

FW_DIR=""
for d in /opt/homebrew/share/qemu /usr/local/share/qemu /usr/share/qemu /usr/share/edk2-ovmf; do
    if [[ -f "$d/edk2-x86_64-code.fd" ]]; then
        FW_DIR="$d"
        break
    fi
done
[[ -n "$FW_DIR" ]] || {
    echo "找不到 OVMF 固件 (edk2-x86_64-code.fd)。macOS: brew install qemu" >&2
    exit 1
}
[[ -f "$VARS" ]] || cp "$FW_DIR/edk2-i386-vars.fd" "$VARS" 2>/dev/null \
    || cp "$FW_DIR/edk2-x86_64-vars.fd" "$VARS"
[[ -f "$VARS" ]] || { echo "无法准备 OVMF vars 文件（$FW_DIR）" >&2; exit 1; }

ACCEL_OPTS=()
case "$(uname -m)" in
    x86_64) MACHINE="q35,accel=hvf"; CPU="host" ;;
    *)
        MACHINE="q35"; CPU="max"
        ACCEL_OPTS=(-accel "tcg,thread=multi")
        echo "提示：Apple Silicon 上以 TCG 模拟 x86_64，安装会明显变慢（建议 PROFILE=smoke）" >&2
        ;;
esac

echo "ISO   : $ISO"
echo "Disk  : $DISK"
echo "内存  : ${MEM}MB  CPU: $CPUS  加速: $MACHINE ${ACCEL_OPTS[*]:-}"
echo "共享  : $REPO_ROOT -> 9p mount_tag=repo"
echo "SSH   : localhost:$PORT -> 22（装好之后）"
echo "QMP   : $QMP（调试/截图用）"

rm -f "$QMP"
exec "$QEMU" \
    -name rice-merge-vm \
    -machine "$MACHINE" \
    ${ACCEL_OPTS[@]+"${ACCEL_OPTS[@]}"} \
    -cpu "$CPU" \
    -smp "$CPUS" \
    -m "$MEM" \
    -drive if=pflash,format=raw,readonly=on,file="$FW_DIR/edk2-x86_64-code.fd" \
    -drive if=pflash,format=raw,file="$VARS" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -cdrom "$ISO" \
    -boot order=cd \
    -device virtio-rng-pci \
    -virtfs "local,path=$REPO_ROOT,mount_tag=repo,security_model=none,readonly=on" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp::$PORT-:22" \
    -qmp "unix:$QMP,server=on,wait=off" \
    -vga none \
    -device VGA,vgamem_mb=64,xres=1024,yres=768 \
    -device qemu-xhci -device usb-kbd -device usb-tablet \
    -serial "file:$VM_DIR/serial.log" \
    -display "$VM_DISPLAY"
