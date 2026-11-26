#!/usr/bin/env bash
# 调用 diskimage-builder 构建整盘 VHD。必须以 root 运行（DIB 要用 loop 设备与 chroot）。
#   sudo env "PATH=$PATH" "BUILD_DIR=$BUILD_DIR" bash scripts/build-image.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

BUILD_DIR=${BUILD_DIR:-$REPO_ROOT/.build}
CONFIG=${CONFIG:-$BUILD_DIR/ubuntu-ventoy.yaml}
DIB_VENV=${DIB_VENV:-$REPO_ROOT/.venv-dib}

if [ "$(id -u)" != "0" ]; then
    echo "需要 root 权限：请用 sudo env \"PATH=\$PATH\" bash scripts/build-image.sh" >&2
    echo "（GitHub runner 的 sudoers 不支持 sudo -E，变量请用 sudo env 显式传入）" >&2
    exit 1
fi

[ -x "$DIB_VENV/bin/diskimage-builder" ] || { echo "未找到 DIB，请先跑 scripts/install-deps.sh" >&2; exit 1; }
export PATH="$DIB_VENV/bin:$PATH"

[ -f "$CONFIG" ] || bash scripts/render-config.sh

# 构建期的临时目录放在数据盘，避开 tmpfs 容量限制
export TMPDIR=${TMPDIR:-$BUILD_DIR/tmp}
mkdir -p "$TMPDIR"
export HOME=${HOME:-/root}
export no_proxy="127.0.0.1,localhost,::1,${no_proxy:-}"
export DIB_DEBUG_REPO=0
export DIB_DEBUG_METADATA=0

echo "== 镜像定义 =="
cat "$CONFIG"
echo
echo "== 磁盘 =="; df -h / "$BUILD_DIR" 2>/dev/null || df -h /

if [ "${DRY_RUN:-0}" = "1" ]; then
    diskimage-builder --dry-run "$CONFIG"
    exit 0
fi

echo "构建开始 $(date -u '+%F %T UTC')"
date +%s > "$BUILD_DIR/build-start.ts"
diskimage-builder --stop-on-failure "$CONFIG"
echo "构建结束 $(date -u '+%F %T UTC')，用时 $(( $(date +%s) - $(cat "$BUILD_DIR/build-start.ts") ))s"

echo "== 产物 =="
ls -l "$BUILD_DIR/out"
du -sh "$BUILD_DIR/out"/*
