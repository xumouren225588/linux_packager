#!/usr/bin/env bash
# 把 DIB 产出的动态扩展 VHD 转成 Ventoy 要求的固定大小 VHD，
# 并按 Linux vDisk 插件要求命名成 xxx.vhd.vtoy。
#
# 用法: postprocess.sh <源文件.vhd> [输出目录]
#   KEEP_SOURCE=1  保留 DIB 原始产物（默认删除以省磁盘）
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

SRC=${1:-}
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "用法: postprocess.sh <源文件.vhd> [输出目录]" >&2
    exit 1
fi
OUT_DIR=${2:-$(dirname "$SRC")}
KEEP_SOURCE=${KEEP_SOURCE:-0}

command -v qemu-img >/dev/null 2>&1 || { echo "缺少 qemu-img，请先跑 scripts/install-deps.sh" >&2; exit 1; }

base=$(basename "$SRC")
case "$base" in
    *.vhd) stem=${base%.vhd} ;;
    *) echo "只接受 .vhd 输入，当前是 $base" >&2; exit 1 ;;
esac

mkdir -p "$OUT_DIR"
DST="$OUT_DIR/$stem.vhd.vtoy"
TMP="$OUT_DIR/.$stem.fixed.tmp"
rm -f "$TMP"

echo "== 源镜像 =="
qemu-img info "$SRC"

# 已经是固定大小就跳过转换（CI 重跑时省一次几十 GB 的读写）
if python3 "$REPO_ROOT/tools/check-vhd.py" --expect-fixed "$SRC" >/dev/null 2>&1; then
    echo "源镜像已是固定大小 VHD，直接命名交付"
    python3 "$REPO_ROOT/tools/check-vhd.py" --expect-fixed "$SRC" || true
    mv "$SRC" "$DST"
    echo "$DST"
    exit 0
fi
python3 "$REPO_ROOT/tools/check-vhd.py" "$SRC" || true

# Ventoy Linux vDisk：只支持固定大小 vhd（不支持 vhdx），动态扩展会启动失败
qemu-img convert -p -f vpc -O vpc -o subformat=fixed "$SRC" "$TMP"

# 硬校验：以 VHD footer 的 Disk type 字段为准（fixed VHD 会被 qemu-img 探测成 raw，
# 所以不能拿 qemu-img 的 format 字段当判据）
python3 "$REPO_ROOT/tools/check-vhd.py" --expect-fixed "$TMP"

mv "$TMP" "$DST"
[ "$KEEP_SOURCE" = "1" ] || rm -f "$SRC"

echo "== 交付文件 =="
ls -l "$DST"
echo "$DST"
