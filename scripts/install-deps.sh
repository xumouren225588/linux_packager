#!/usr/bin/env bash
# 在构建机（Ubuntu 22.04 / 24.04）上安装 DIB 与全部构建依赖。
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DIB_VENV=${DIB_VENV:-$REPO_ROOT/.venv-dib}
DIB_VERSION=${DIB_VERSION:-}          # 留空=latest；需要复现时钉版本，如 3.32.0

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    git curl ca-certificates python3 python3-pip python3-venv \
    debootstrap qemu-utils gdisk parted e2fsprogs dosfstools squashfs-tools \
    xz-utils zstd rsync gettext-base file jq sudo

python3 -m venv "$DIB_VENV"
"$DIB_VENV/bin/pip" install --upgrade pip wheel
if [ -n "$DIB_VERSION" ]; then
    "$DIB_VENV/bin/pip" install "diskimage-builder==$DIB_VERSION"
else
    "$DIB_VENV/bin/pip" install diskimage-builder
fi

echo "已安装：$("$DIB_VENV/bin/disk-image-create" --version)"
df -h | sed -n '1,3p'
