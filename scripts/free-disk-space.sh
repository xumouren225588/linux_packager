#!/usr/bin/env bash
# 清理 GitHub 托管 runner 上的预装软件，为整盘镜像构建腾出空间。
# 自建 runner 上设 SKIP_DISK_FREE=1 跳过（避免误删本机软件）。
set -uo pipefail

[ "${SKIP_DISK_FREE:-0}" = "1" ] && exit 0

echo "== 清理前 =="; df -h /

PATHS=(
    /usr/share/dotnet
    /usr/local/share/dotnet
    /usr/local/lib/android
    /opt/ghc
    /usr/local/.ghcup
    /opt/hostedtoolcache
    /usr/share/swift
    /usr/share/powershell
    /usr/local/share/powershell
    /usr/share/miniconda
    /usr/local/graalvm
    /usr/local/lib/heroku
    /usr/local/share/chrome-driver
    /usr/local/lib/node_modules
    /usr/share/bicep
    /opt/mssql-tools*
    /usr/lib/llvm-*
    /usr/local/share/boost
    /usr/share/gradle*
    /usr/share/maven
    /usr/local/phantomjs
    /usr/local/share/edge_driver
    /usr/local/lib/android/sdk
)

for p in "${PATHS[@]}"; do
    # shellcheck disable=SC2086
    for m in $p; do
        [ -e "$m" ] || continue
        sudo du -sh "$m" 2>/dev/null || true
        sudo rm -rf "$m"
    done
done

# Docker 镜像会占用数十 GB（runner 预装了 node/python 镜像）
if command -v docker >/dev/null 2>&1; then
    docker system prune -af >/dev/null 2>&1 || true
fi

sudo apt-get clean || true
sudo journalctl --rotate --vacuum-time=1s >/dev/null 2>&1 || true
[ -d /var/log ] && sudo rm -rf /var/log/*.gz /var/log/*.1 2>/dev/null || true

echo "== 清理后 =="; df -h /
