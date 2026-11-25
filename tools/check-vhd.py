#!/usr/bin/env python3
"""直接解析 VHD footer，判定镜像是否满足 Ventoy Linux vDisk 的硬性要求。

为什么不用 `qemu-img info` 的 format 字段下结论：固定大小 VHD 没有文件头，
只有文件末尾 512 字节的 footer，qemu-img 自动探测时会把它认成 raw
（实测 qemu-img 4.x 行为）。footer 里的 Disk type 字段才是权威依据。

VHD footer（文件最后 512 字节，多字节字段全为大端）：
  offset  0  cookie        "conect"
  offset 16  data_offset   固定大小为 0xFFFFFFFF
  offset 40  original_size 创建时大小（字节）
  offset 48  current_size  虚拟磁盘大小（字节）
  offset 60  disk_type     2=Fixed, 3=Dynamic, 4=Differencing

注意 footer 的位置：固定大小 VHD 的 footer 在文件最末尾；动态扩展 VHD 的
footer 后面还跟着 BAT 等元数据，因此不能一概按“末尾 512 字节”去读动态镜像。
脚本先按末尾取，取不到 conect 时再回退扫描 data_offset 指向的位置。

用法: check-vhd.py [--expect-fixed] <file.vhd|file.vhd.vtoy>
退出码 0=满足要求，1=不满足。
"""
from __future__ import annotations

import os
import struct
import sys

DISK_TYPES = {2: "Fixed", 3: "Dynamic", 4: "Differencing"}


def read_footer(path: str) -> dict:
    size = os.path.getsize(path)
    if size < 512:
        raise SystemExit(f"FAIL: {path} 只有 {size} 字节，不可能含 VHD footer")
    with open(path, "rb") as fh:
        fh.seek(-512, os.SEEK_END)
        footer = fh.read(512)
        if footer[:6] != b"conect":
            # 动态扩展 VHD：footer 在 BAT 之前，位置由文件头的 max_table_offset 指明
            fh.seek(640)
            header = fh.read(512)
            max_table_offset = struct.unpack(">Q", header[128:136])[0]
            if max_table_offset and max_table_offset < size:
                fh.seek(max_table_offset)
                footer = fh.read(512)
        if footer[:6] != b"conect":
            raise SystemExit(f"FAIL: {path} 找不到 conect 标识，不是 VHD 文件")
    data_offset = struct.unpack(">I", footer[16:20])[0]
    original_size = struct.unpack(">Q", footer[40:48])[0]
    current_size = struct.unpack(">Q", footer[48:56])[0]
    disk_type = struct.unpack(">I", footer[60:64])[0]
    return {
        "path": path,
        "file_size": size,
        "data_offset": data_offset,
        "original_size": original_size,
        "current_size": current_size,
        "disk_type": disk_type,
        "disk_type_name": DISK_TYPES.get(disk_type, f"unknown({disk_type})"),
        "is_fixed": disk_type == 2,
    }


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    expect_fixed = "--expect-fixed" in sys.argv[1:] or "--fixed" in sys.argv[1:]
    if not args:
        print(__doc__)
        return 2

    ok = True
    for path in args:
        info = read_footer(path)
        print(
            f"{os.path.basename(path)}: disk_type={info['disk_type_name']} "
            f"data_offset=0x{info['data_offset']:08X} "
            f"virtual={info['current_size']} file={info['file_size']}"
        )
        if info["is_fixed"]:
            # 固定大小 VHD = 虚拟大小 + 512 字节 footer，一字节不多一字节不少
            if info["file_size"] != info["current_size"] + 512:
                print(f"FAIL: 固定大小 VHD 文件大小应为 {info['current_size'] + 512}，实际 {info['file_size']}")
                ok = False
            if info["data_offset"] != 0xFFFFFFFF:
                print(f"FAIL: data_offset=0x{info['data_offset']:08X}，固定大小应为 0xFFFFFFFF")
                ok = False
        elif expect_fixed:
            print("FAIL: 这是动态扩展 VHD，Ventoy 的 Linux vDisk 插件启动不了，需要转成固定大小")
            ok = False

    if not ok:
        return 1
    print("OK: VHD 格式满足 Ventoy Linux vDisk 要求" if expect_fixed else "OK: VHD footer 解析正常")
    return 0


if __name__ == "__main__":
    sys.exit(main())
