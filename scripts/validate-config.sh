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
    dd if=/dev/zero of=$tmpd/z bs=1M count=8 status=none
    qemu-img convert -f raw -O vpc -o subformat=fixed $tmpd/z $tmpd/t.vhd
    if python3 tools/check-vhd.py --expect-fixed $tmpd/t.vhd; then
        :
    else
        echo "  ERR check-vhd.py 未能识别刚生成的固定大小 VHD"; fail=1
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
