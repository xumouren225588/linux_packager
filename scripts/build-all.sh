#!/usr/bin/env bash
# 一条命令跑完整流程（本地或自建 runner 上用；CI 里是分步的）。
#   UBUNTU_RELEASE=noble IMAGE_SIZE=20 sudo env "PATH=$PATH" bash scripts/build-all.sh
# 注意：sudo -E 在 GitHub runner 上会被 sudoers 拒绝（-E is ignored），
# 需要保留环境时用 sudo env "PATH=$PATH" "VAR=$VAR" 的形式显式传值。
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
BUILD_DIR=${BUILD_DIR:-$REPO_ROOT/.build}

bash scripts/install-deps.sh
bash scripts/fetch-vtoyboot.sh "${VTOYBOOT_VERSION:-latest}"
bash scripts/render-config.sh
# 元素脚本要可执行权限（git 会保留，但从 zip 取出时可能丢失）
chmod +x "$REPO_ROOT"/elements/ubuntu-ventoy-gnome/finalise.d/*

sudo env "PATH=$PATH" "BUILD_DIR=$BUILD_DIR" "OUTPUT_FORMAT=${OUTPUT_FORMAT:-raw}" \
    "DIB_VENV=${DIB_VENV:-$REPO_ROOT/.venv-dib}" \
    bash scripts/build-image.sh

SRC=""
set -a; . "$BUILD_DIR/vars.env"; set +a
for cand in "$IMAGENAME.raw" "$IMAGENAME.img" "$IMAGENAME.vhd" "$IMAGENAME.qcow2"; do
    [ -f "$cand" ] && SRC="$cand" && break
done
[ -n "$SRC" ] || SRC=$(ls -1 "$BUILD_DIR"/out/*.raw "$BUILD_DIR"/out/*.vhd 2>/dev/null | head -n1)
[ -n "$SRC" ] || { echo "找不到 DIB 产物" >&2; ls -lR "$BUILD_DIR/out" >&2; exit 1; }
bash scripts/postprocess.sh "$SRC" "$BUILD_DIR/out"
DST=$(ls -1 "$BUILD_DIR"/out/*.vhd.vtoy | head -n1)
bash scripts/pack-artifact.sh "$DST"
ls -l "$BUILD_DIR"/out/dist
