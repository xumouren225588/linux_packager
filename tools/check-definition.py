#!/usr/bin/env python3
"""校验渲染后的 DIB 镜像定义，抢在正式构建之前抓出配置层错误。

用法: tools/check-definition.py [.build/ubuntu-ventoy.yaml]
退出码非 0 表示定义有问题。
"""
import os
import sys

import yaml


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else ".build/ubuntu-ventoy.yaml"
    if not os.path.isfile(path):
        print(f"FAIL: 找不到 {path}，请先跑 scripts/render-config.sh")
        return 1

    doc = yaml.safe_load(open(path, encoding="utf-8"))
    if not isinstance(doc, list) or not doc:
        print("FAIL: 顶层必须是非空的镜像定义列表")
        return 1

    errors: list[str] = []
    for img in doc:
        name = img.get("imagename", "<未命名>")

        # 只允许 DIB YAML 包装命令认识的键，杜绝 image-type 这类写法
        allowed = {
            "imagename", "arch", "types", "environment", "ramdisk", "debug-trace",
            "uncompressed", "clear", "logfile", "checksum", "image-size",
            "image-extra-size", "image-cache", "max-online-resize", "min-tmpfs",
            "mkfs-journal-size", "mkfs-options", "no-tmpfs", "offline",
            "qemu-img-options", "root-label", "ramdisk-element", "install-type",
            "docker-target", "packages", "skip-base", "elements",
        }
        unknown = sorted(set(img) - allowed)
        if unknown:
            errors.append(f"{name}: 存在 DIB 不认识的键 {unknown}（输出格式请用 types 列表）")

        if img.get("types") != ["vhd"]:
            errors.append(f"{name}: types 应为 [\"vhd\"]，当前是 {img.get('types')}")
        if not isinstance(img.get("image-size"), int):
            errors.append(f"{name}: image-size 必须是整数（GB）")

        elements = img.get("elements") or []
        for required in ("ubuntu-minimal", "vm", "block-device-gpt", "ubuntu-ventoy-gnome"):
            if required not in elements:
                errors.append(f"{name}: 缺少必需元素 {required}")

        env = img.get("environment") or {}
        desktop = env.get("DIB_VENTOY_DESKTOP")
        if desktop not in ("gnome", "xfce", "none"):
            errors.append(f"{name}: DIB_VENTOY_DESKTOP 非法: {desktop}")
        elements_path = env.get("ELEMENTS_PATH", "")
        if not os.path.isdir(elements_path):
            errors.append(f"{name}: ELEMENTS_PATH 不存在: {elements_path}")
        else:
            custom = os.path.join(elements_path, "ubuntu-ventoy-gnome")
            if not os.path.isdir(custom):
                errors.append(f"{name}: 自定义元素缺失: {custom}")

    if errors:
        for e in errors:
            print("FAIL:", e)
        return 1

    print(f"OK: 镜像定义检查通过 -> {doc[0]['imagename']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
