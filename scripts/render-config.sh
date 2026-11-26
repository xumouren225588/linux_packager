#!/usr/bin/env bash
# 把 config/ubuntu-ventoy.yaml.in 渲染成可直接交给 diskimage-builder 的 YAML。
# 所有可调参数都通过环境变量传入，CI 与本地共用同一套入口。
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$REPO_ROOT/.build}

UBUNTU_RELEASE=${UBUNTU_RELEASE:-noble}
IMAGE_SIZE=${IMAGE_SIZE:-20}
DESKTOP=${DESKTOP:-gnome}
USERNAME=${DEV_USERNAME:-user}
USERPASS=${DEV_PASSWORD:-1234}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-raw}

# DIB 的 vhd 类型依赖 vhd-util（Ubuntu/Debian 仓库里没有这个包）。
# 明确要求 vhd 但工具缺失时自动降级为 raw，避免整条流水线因为缺工具而失败；
# 后处理脚本会把 raw 转成 Ventoy 需要的固定大小 VHD，交付物不变。
case "$OUTPUT_FORMAT" in
    raw|qcow2) : ;;
    vhd)
        if ! command -v vhd-util >/dev/null 2>&1; then
            echo "WARN: 系统没有 vhd-util，DIB 无法直接产出 vhd；改用 raw 由 qemu-img 转换" >&2
            OUTPUT_FORMAT=raw
        fi
        ;;
    *) echo "不支持的 OUTPUT_FORMAT: $OUTPUT_FORMAT（可选 raw / qcow2 / vhd）" >&2; exit 1 ;;
esac

case "$DESKTOP" in
    gnome) flavor=gnome ;;
    xfce)  flavor=xfce ;;
    none)  flavor=server ;;
    *) echo "不支持的 DESKTOP: $DESKTOP（可选 gnome / xfce / none）" >&2; exit 1 ;;
esac

export IMAGENAME=${IMAGENAME:-$BUILD_DIR/out/ubuntu-${UBUNTU_RELEASE}-${flavor}-ventoy}
export IMAGE_SIZE
export DIB_RELEASE=$UBUNTU_RELEASE
export DIB_VENTOY_DESKTOP=$DESKTOP
export DIB_DEV_USER_USERNAME=$USERNAME
export DIB_DEV_USER_PASSWORD=$USERPASS
export ELEMENTS_PATH=${ELEMENTS_PATH:-$REPO_ROOT/elements}
export OUTPUT_FORMAT

mkdir -p "$BUILD_DIR/out"

# 只替换明确列出的占位符，其余 $ 记号原样保留
VARS='${IMAGENAME} ${OUTPUT_FORMAT} ${IMAGE_SIZE} ${DIB_RELEASE} ${DIB_VENTOY_DESKTOP} ${DIB_DEV_USER_USERNAME} ${DIB_DEV_USER_PASSWORD} ${ELEMENTS_PATH}'
envsubst "$VARS" < "$REPO_ROOT/config/ubuntu-ventoy.yaml.in" > "$BUILD_DIR/ubuntu-ventoy.yaml"

cat > "$BUILD_DIR/vars.env" <<EOF
IMAGENAME=$IMAGENAME
IMAGE_SIZE=$IMAGE_SIZE
DIB_RELEASE=$DIB_RELEASE
DIB_VENTOY_DESKTOP=$DESKTOP
FLAVOR=$flavor
OUTPUT_FORMAT=$OUTPUT_FORMAT
CONFIG=$BUILD_DIR/ubuntu-ventoy.yaml
EOF

echo "渲染完成: $BUILD_DIR/ubuntu-ventoy.yaml"
echo "DIB 输出格式: $OUTPUT_FORMAT -> $IMAGENAME.$OUTPUT_FORMAT"
echo "（后处理会统一转成 Ventoy 需要的固定大小 xxx.vhd.vtoy）"
