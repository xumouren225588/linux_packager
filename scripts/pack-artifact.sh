#!/usr/bin/env bash
# 把交付镜像压缩 + 生成校验和 +（可选）分卷，得到适合上传的工件。
#
# 用法: pack-artifact.sh <镜像文件> [输出目录]
#   COMPRESSION=zstd|xz|none   默认 zstd
#   SPLIT_MB=0                 0=不分卷；否则按 MiB 分卷（绕开单文件大小限制）
#
# 固定大小 VHD 的未使用区域全是零，压缩比极高：20GB 镜像通常能压到 1~3GB。
set -euo pipefail

SRC=${1:-}
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
    echo "用法: pack-artifact.sh <镜像文件> [输出目录]" >&2
    exit 1
fi
OUT_DIR=${2:-$(dirname "$SRC")/dist}
METHOD=${COMPRESSION:-zstd}
SPLIT_MB=${SPLIT_MB:-0}
LEVEL=${COMPRESSION_LEVEL:-}

mkdir -p "$OUT_DIR"
name=$(basename "$SRC")

case "$METHOD" in
    zstd)
        command -v zstd >/dev/null 2>&1 || { echo "缺少 zstd" >&2; exit 1; }
        ART="$OUT_DIR/$name.zst"
        zstd -T0 -"${LEVEL:-19}" -q -f "$SRC" -o "$ART"
        ;;
    xz)
        xz -T0 -"${LEVEL:-6}" -k -f -c "$SRC" > "$OUT_DIR/$name.xz"
        ART="$OUT_DIR/$name.xz"
        ;;
    none)
        cp -f "$SRC" "$OUT_DIR/$name"
        ART="$OUT_DIR/$name"
        ;;
    *)
        echo "COMPRESSION 只支持 zstd / xz / none" >&2; exit 1 ;;
esac

(cd "$OUT_DIR" && sha256sum "$(basename "$ART")" > "$(basename "$ART").sha256")

if [ "$SPLIT_MB" != "0" ] && [ -n "$SPLIT_MB" ]; then
    (cd "$OUT_DIR" && split -b "${SPLIT_MB}m" -d -a 3 "$(basename "$ART")" "$(basename "$ART").part-")
    cat > "$OUT_DIR/RESTORE.txt" <<EOF
工件已按 ${SPLIT_MB} MiB 分卷，还原方法：

  cat $(basename "$ART").part-* > $(basename "$ART")
  sha256sum -c $(basename "$ART").sha256   # 或在下载目录用随附的 .sha256

解压（${METHOD}）：
$([ "$METHOD" = "zstd" ] && echo "  zstd -d $(basename "$ART") -o ${name}" || ([ "$METHOD" = "xz" ] && echo "  xz -d -k $(basename "$ART") > ${name}" || echo "  无需解压"))

解压后文件应命名为 xxx.vhd.vtoy，直接拷到 Ventoy U 盘存放镜像的分区根目录即可。
EOF
fi

echo "== dist 目录 =="
ls -l "$OUT_DIR"
echo "源大小 / 工件大小:"
du -h "$SRC" "$ART" | sed 's/\t/  /'
echo "ARTIFACT=$ART"
