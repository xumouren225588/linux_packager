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

mkdir -p "$BUILD_DIR/out"

# 只替换明确列出的占位符，其余 $ 记号原样保留
VARS='${IMAGENAME} ${IMAGE_SIZE} ${DIB_RELEASE} ${DIB_VENTOY_DESKTOP} ${DIB_DEV_USER_USERNAME} ${DIB_DEV_USER_PASSWORD} ${ELEMENTS_PATH}'
envsubst "$VARS" < "$REPO_ROOT/config/ubuntu-ventoy.yaml.in" > "$BUILD_DIR/ubuntu-ventoy.yaml"

cat > "$BUILD_DIR/vars.env" <<EOF
IMAGENAME=$IMAGENAME
IMAGE_SIZE=$IMAGE_SIZE
DIB_RELEASE=$DIB_RELEASE
DIB_VENTOY_DESKTOP=$DESKTOP
FLAVOR=$flavor
CONFIG=$BUILD_DIR/ubuntu-ventoy.yaml
EOF

echo "渲染完成: $BUILD_DIR/ubuntu-ventoy.yaml"
echo "输出镜像: $IMAGENAME.vhd"
