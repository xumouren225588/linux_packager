#!/usr/bin/env bash
# 不真正构建的静态校验：脚本语法 + YAML 合法性 + DIB 元素解析（dry-run）。
# 与 .github/workflows/validate.yml 跑的是同一套检查。
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"
BUILD_DIR=${BUILD_DIR:-$REPO_ROOT/.build}
export BUILD_DIR

fail=0

echo "== 1. shell 语法 =="
while IFS= read -r f; do
    if bash -n "$f"; then
        echo "  OK  ${f#$REPO_ROOT/}"
    else
        echo "  ERR ${f#$REPO_ROOT/}"; fail=1
    fi
done < <(find scripts elements -type f \( -name '*.sh' -o -path '*/*.d/*' \) | sort)

echo "== 2. 元素脚本可执行位 =="
for f in elements/*/finalise.d/*; do
    if [ -x "$f" ]; then echo "  OK  ${f#$REPO_ROOT/}"; else echo "  ERR ${f#$REPO_ROOT/} 缺少可执行位"; fail=1; fi
done

echo "== 3. YAML 解析 =="
python3 - <<'PY' || fail=1
import glob, sys, yaml
bad = False
for f in sorted(glob.glob(".github/workflows/*.yml") + glob.glob("elements/**/*.yaml", recursive=True)):
    try:
        list(yaml.safe_load_all(open(f)))
        print(f"  OK  {f}")
    except Exception as e:
        print(f"  ERR {f}: {e}")
        bad = True
sys.exit(1 if bad else 0)
PY

echo "== 4. 渲染镜像定义 =="
bash scripts/render-config.sh

echo "== 5. 镜像定义语义检查 =="
if python3 tools/check-definition.py "$BUILD_DIR/ubuntu-ventoy.yaml"; then
    :
else
    fail=1
fi

echo "== 6. VHD footer 工具自检（构造 fixed VHD 后验证解析）=="
if command -v qemu-img >/dev/null 2>&1; then
    tmpd=$(mktemp -d)
    # 造一个含 GPT 主/备头的 raw 整盘镜像，模拟 DIB 的真实输出
    python3 - "$tmpd/gpt.raw" <<'GPT'
import sys
SIZE, SECT = 8 * 1024 * 1024, 512
last = SIZE // SECT - 1
buf = bytearray(SIZE)
buf[0x1C2] = 0xEE; buf[510:512] = b"\x55\xAA"
for lba in (1, last):
    h = bytearray(SECT); h[0:8] = b"EFI PART"
    h[16:24] = lba.to_bytes(8, "little")
    h[24:32] = (last if lba == 1 else 1).to_bytes(8, "little")
    buf[lba * SECT:lba * SECT + SECT] = h
open(sys.argv[1], "wb").write(buf)
GPT
    qemu-img convert -f raw -O vpc -o subformat=fixed,force_size $tmpd/gpt.raw $tmpd/t.vhd
    if python3 tools/check-vhd.py --expect-fixed $tmpd/t.vhd | grep -q "GPT 主头/备份头位置正确"; then
        echo "  OK  fixed VHD + GPT 位置校验通过"
    else
        echo "  ERR 固定大小转换或 GPT 位置校验未通过"; fail=1
    fi
    # 反向用例：不带 force_size 时容量会被放大，必须被检查器拒绝
    qemu-img convert -f raw -O vpc -o subformat=fixed $tmpd/gpt.raw $tmpd/bad.vhd
    if python3 tools/check-vhd.py --expect-fixed $tmpd/bad.vhd >/dev/null 2>&1; then
        echo "  ERR 缺少 force_size 的镜像本应被拒绝"; fail=1
    else
        echo "  OK  不带 force_size 的镜像被正确拒绝"
    fi
    rm -rf $tmpd
else
    echo "  SKIP 未安装 qemu-img"
fi

echo "== 7. DIB dry-run（校验元素名与自定义元素依赖）=="
if [ -x "${DIB_VENV:-$REPO_ROOT/.venv-dib}/bin/diskimage-builder" ]; then
    export PATH="${DIB_VENV:-$REPO_ROOT/.venv-dib}/bin:$PATH"
else
    command -v diskimage-builder >/dev/null 2>&1 || { echo "  SKIP 未安装 diskimage-builder"; exit 0; }
fi
diskimage-builder --dry-run "$BUILD_DIR/ubuntu-ventoy.yaml"

[ "$fail" = 0 ] && echo "全部校验通过" || { echo "存在校验失败项"; exit 1; }
