#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""校验 rockchip sysupgrade 镜像 MBR 分区表里的 rootfs_data 分区大小。

背景：上游 Build/pine64-img 调用 gen_image_generic.sh 时没有设置 PADDING，
脚本只在 [ -n "$PADDING" ] 时才把 userdata 分区 dd 填零，所以镜像文件本身
只有 kernel + rootfs（约 216 MiB），但分区表里 userdata 标称 4096 MiB。
因此不能用「镜像体积 >= 4.2 GiB」来判断，必须读分区表。

只读 gzip 流的前 512 字节即可取到 MBR，无需解压整盘。
用法：python3 scripts/check-partition-table.py <image.img.gz> [expect_MiB]
"""
import gzip
import os
import struct
import sys

EXPECT_DEFAULT = int(os.environ.get("ROOTFS_DATA_PARTSIZE", "4096"))


def read_mbr(path):
    with gzip.open(path, "rb") as f:
        mbr = f.read(512)
    if len(mbr) < 512 or mbr[510:512] != b"\x55\xaa":
        raise RuntimeError("缺少有效 MBR 分区表（若上游改为 GPT，需同步改这里的解析）")
    parts = []
    for i in range(4):
        e = mbr[446 + 16 * i: 462 + 16 * i]
        ptype, start, size = e[4], struct.unpack_from("<I", e, 8)[0], struct.unpack_from("<I", e, 12)[0]
        if size:
            parts.append((ptype, start, size))
    return parts


def main():
    if len(sys.argv) < 2:
        print("用法: check-partition-table.py <image.img.gz> [expect_MiB]", file=sys.stderr)
        return 2
    img, expect = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else EXPECT_DEFAULT
    parts = read_mbr(img)
    print("MBR 分区表（type / start_LBA / sectors / MiB）：")
    for t, a, n in parts:
        print("  0x%02x  %10d  %10d  %8.1f" % (t, a, n, n * 512 / 1024 / 1024))
    if not parts:
        raise RuntimeError("分区表为空")
    # userdata 是最大的分区（kernel 16 / rootfs 500 / rootfs_data 4096）
    userdata = max(parts, key=lambda x: x[2])[2] * 512
    want = expect * 1024 * 1024
    if abs(userdata - want) > 16 * 1024 * 1024:
        raise RuntimeError("rootfs_data 分区仅 %.1f MiB，期望 %d MiB"
                           "（检查 apply-device.sh 的 USERDATASIZE 改写）"
                           % (userdata / 1024 / 1024, expect))
    print("[OK] rootfs_data 分区 = %.0f MiB（期望 %d MiB）" % (userdata / 1024 / 1024, expect))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("::error::%s" % exc, file=sys.stderr)
        sys.exit(1)
