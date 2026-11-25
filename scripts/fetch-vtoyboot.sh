#!/usr/bin/env bash
# 把 Ventoy 官方 vtoyboot 载荷下载到元素的 data/ 目录，供离线构建使用。
# 用法: fetch-vtoyboot.sh [latest|1.0.42]
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=${1:-${VTOYBOOT_VERSION:-latest}}
DATA_DIR=$REPO_ROOT/elements/ubuntu-ventoy-gnome/ventoy-data
DEST=$DATA_DIR/vtoyboot.tar.gz

mkdir -p "$DATA_DIR"
if [ -s "$DEST" ] && [ "${FORCE_DOWNLOAD:-0}" != "1" ]; then
    echo "已存在载荷，跳过下载: $DEST"
    exit 0
fi

URL=""
if [ "$VERSION" = "latest" ]; then
    # 优先用 gh（认证请求，避开匿名 API 限流），失败再退回裸 curl
    if command -v gh >/dev/null 2>&1 && [ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
        URL=$(gh api repos/ventoy/vtoyboot/releases/latest \
              --jq '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' 2>/dev/null | head -n1)
    fi
    if [ -z "$URL" ]; then
        URL=$(curl -sSL https://api.github.com/repos/ventoy/vtoyboot/releases/latest \
              | grep -o 'https://[^"]*\.tar\.gz' | head -n1)
    fi
else
    URL="https://github.com/ventoy/vtoyboot/releases/download/${VERSION}/vtoyboot-${VERSION}.tar.gz"
fi

if [ -z "$URL" ]; then
    echo "WARN: 未能解析 vtoyboot 下载地址；构建期会改由镜像内在线下载兜底" >&2
    exit 0
fi

echo "下载 $URL"
if ! curl -fL --retry 3 --retry-delay 2 -o "$DEST" "$URL"; then
    rm -f "$DEST"
    echo "WARN: 载荷下载失败；构建期会改由镜像内在线下载兜底" >&2
    exit 0
fi

ls -l "$DEST"
sha256sum "$DEST"
