#!/usr/bin/env bash
# 一条命令跑完整流程（本地或自建 runner 上用；CI 里是分步的）。
#   UBUNTU_RELEASE=noble IMAGE_SIZE=20 sudo -E env "PATH=$PATH" bash scripts/build-all.sh
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
BUILD_DIR=${BUILD_DIR:-$REPO_ROOT/.build}

bash scripts/install-deps.sh
bash scripts/fetch-vtoyboot.sh "${VTOYBOOT_VERSION:-latest}"
bash scripts/render-config.sh
# 元素脚本要可执行权限（git 会保留，但从 zip 取出时可能丢失）
chmod +x "$REPO_ROOT"/elements/ubuntu-ventoy-gnome/finalise.d/*

sudo -E env "PATH=$PATH" "BUILD_DIR=$BUILD_DIR" "DIB_VENV=${DIB_VENV:-$REPO_ROOT/.venv-dib}" \
    bash scripts/build-image.sh

SRC=$(ls -1 "$BUILD_DIR"/out/*.vhd | head -n1)
bash scripts/postprocess.sh "$SRC" "$BUILD_DIR/out"
DST=$(ls -1 "$BUILD_DIR"/out/*.vhd.vtoy | head -n1)
bash scripts/pack-artifact.sh "$DST"
ls -l "$BUILD_DIR"/out/dist
