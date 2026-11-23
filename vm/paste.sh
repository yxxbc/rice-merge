#!/usr/bin/env bash
# 把宿主机剪贴板（pbpaste）打进正在运行的 QEMU guest。
#
#   bash vm/paste.sh                  # 粘贴剪贴板并回车
#   bash vm/paste.sh --no-enter       # 只粘贴，不回车
#   bash vm/paste.sh --text "ls -la"  # 直接指定文本
#
# 原理：QMP send-key 注入键盘事件，所以只支持 ASCII；中文控制台本来也显示不了。
# 需要在 vm/run.sh 启动的 VM（它暴露 vm/qmp.sock）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCK="${QMP_SOCK:-$REPO_ROOT/vm/qmp.sock}"

if [[ "${1:-}" == "--text" ]]; then
    TEXT="${2:?--text 需要参数}"
    shift 2
    exec python3 "$REPO_ROOT/vm/paste.py" --sock "$SOCK" --text "$TEXT" "$@"
fi

exec python3 "$REPO_ROOT/vm/paste.py" --sock "$SOCK" --clipboard "$@"
