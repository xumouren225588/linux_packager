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

# vhd-util 只在选择 OUTPUT_FORMAT=vhd 时才需要；Ubuntu/Debian 仓库通常没有该包，
# 缺省时 render-config.sh 会自动降级为 raw，所以这里装不上也不算错误。
if ! command -v vhd-util >/dev/null 2>&1; then
    sudo apt-get install -y --no-install-recommends vhd-util >/dev/null 2>&1 \
        || echo "提示：无 vhd-util，DIB 输出将使用 raw（后处理仍产出固定大小 VHD）"
fi

echo "已安装：$("$DIB_VENV/bin/disk-image-create" --version)"
df -h | sed -n '1,3p'
