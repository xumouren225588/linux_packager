#!/usr/bin/env bash
# 把 DIB 的产物转成 Ventoy 要求的固定大小 VHD，并命名成 xxx.vhd.vtoy。
#
# 输入可以是 DIB 的 raw 整盘镜像（默认路线，不需要 vhd-util）、qcow2，
# 或 DIB 直接产出的动态扩展 vhd；格式用 qemu-img 探测，不按扩展名猜。
#
# 用法: postprocess.sh <DIB产物> [输出目录]
#   KEEP_SOURCE=1  保留源文件（默认转换后删除，省磁盘）
#   ALSO_RAW=1     额外导出一份 raw 格式的 xxx.img.vtoy（Ventoy 也支持 raw vDisk）
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${1:-}
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "用法: postprocess.sh <DIB产物(.raw/.vhd/.qcow2)> [输出目录]" >&2
    exit 1
fi
OUT_DIR=${2:-$(dirname "$SRC")}
KEEP_SOURCE=${KEEP_SOURCE:-0}
ALSO_RAW=${ALSO_RAW:-0}

command -v qemu-img >/dev/null 2>&1 || { echo "缺少 qemu-img，请先跑 scripts/install-deps.sh" >&2; exit 1; }
CHECK="$REPO_ROOT/tools/check-vhd.py"

base=$(basename "$SRC")
case "$base" in
    *.raw)   stem=${base%.raw} ;;
    *.img)   stem=${base%.img} ;;
    *.vhd)   stem=${base%.vhd} ;;
    *.qcow2) stem=${base%.qcow2} ;;
    *) echo "不支持的输入扩展名: $base（期望 .raw / .img / .vhd / .qcow2）" >&2; exit 1 ;;
esac

mkdir -p "$OUT_DIR"
DST="$OUT_DIR/$stem.vhd.vtoy"
TMP="$OUT_DIR/.$stem.fixed.tmp"
rm -f "$TMP"

# 探测真实格式：DIB 用 raw 输出时这里是 raw；动态 vhd 是 vpc；
# 注意固定大小 vhd 会被探测成 raw，所以判定 fixed 一律靠 footer，不靠这里的 format。
src_fmt=$(qemu-img info --output=json "$SRC" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')
virt_size=$(qemu-img info --output=json "$SRC" | python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual-size"])')
echo "== 源镜像 =="
echo "路径: $SRC  探测格式: $src_fmt  虚拟大小: $virt_size"
qemu-img info "$SRC"

# 源本身已是固定大小 VHD（例如手工喂一个成品）：直接命名交付
if [ "$src_fmt" = "vpc" ] || python3 "$CHECK" "$SRC" >/dev/null 2>&1; then
    if python3 "$CHECK" --expect-fixed "$SRC" >/dev/null 2>&1; then
        echo "源镜像已是固定大小 VHD，直接命名交付"
        python3 "$CHECK" --expect-fixed "$SRC" || true
        mv "$SRC" "$DST"
        echo "$DST"
        exit 0
    fi
fi

# Ventoy Linux vDisk：只接受固定大小 vhd（不支持 vhdx），动态扩展会启动失败。
#
# force_size 是必须的：不带它时 qemu-img 会把 VHD 容量按 CHS 几何向上取整
# （实测 64MiB 的 raw 变成 67125248，多出 16384 字节）。整盘镜像里的 GPT
# 备份头写在"原始最后一个扇区"，容量一旦被放大，备份头就不再位于逻辑磁盘末尾，
# 内核会判定 GPT 损坏（实测 a.vhd 末扇区全零 / b.vhd 末扇区 EFI PART），
# Ventoy 上就会起不来。带上 force_size 后 VHD 容量与源镜像逐字节一致。
echo "== 转换为固定大小 VHD =="
qemu-img convert -p -f "$src_fmt" -O vpc -o subformat=fixed,force_size "$SRC" "$TMP"

# 硬校验：以 VHD footer 的 disk_type 为准（fixed VHD 没有文件头，
# qemu-img 会把它探测成 raw，因此不能拿 qemu-img 的 format 字段当判据）
python3 "$CHECK" --expect-fixed "$TMP"

mv "$TMP" "$DST"

if [ "$ALSO_RAW" = "1" ]; then
    echo "== 额外导出 raw vDisk =="
    qemu-img convert -f "$src_fmt" -O raw "$SRC" "$OUT_DIR/$stem.img.vtoy" \
        || cp "$SRC" "$OUT_DIR/$stem.img.vtoy"
fi

[ "$KEEP_SOURCE" = "1" ] || rm -f "$SRC"

echo "== 交付文件 =="
ls -l "$OUT_DIR"/*.vtoy
echo "$DST"
