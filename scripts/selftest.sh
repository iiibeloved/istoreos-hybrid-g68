#!/bin/sh
# 构建前自检：核心功能守卫 + 板级/镜像/内核补丁检查
set -eu
ROOT="${1:?用法: selftest.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
UB="$ROOT/package/boot/uboot-rockchip"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== 0. 核心功能守卫（长按 Reset→MaskROM）=="
sh "$HERE/scripts/verify-maskrom.sh" "$ROOT" || FAIL=$((FAIL+1))

echo "== 1. 内核 DTS 关键节点 =="
KDTS="$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
for pat in "adc-keys" "io-channels = <&saradc 0>" "&saradc" "recovery-key" "&xpcs"; do
	grep -q "$pat" "$KDTS" 2>/dev/null && ok "kernel dts: $pat" || bad "kernel dts 缺 $pat"
done

echo "== 2. 内核补丁（XPCS / SGMII 2.5G）=="
for p in 910 911 912 913; do
	ls "$ROOT/target/linux/rockchip/patches-6.6/${p}-"*.patch >/dev/null 2>&1 && ok "内核补丁 ${p}-*" || bad "缺内核补丁 ${p}-*"
done

echo "== 3. 构建系统插入 =="
grep -q "U-Boot/nsy-g68-plus-rk3568" "$UB/Makefile" && ok "U-Boot 目标定义" || bad "缺 U-Boot 目标定义"
sed -n '/^UBOOT_TARGETS/,/^$/p' "$UB/Makefile" | grep -q "nsy-g68-plus-rk3568" && ok "UBOOT_TARGETS" || bad "UBOOT_TARGETS 缺目标"
IMG="$ROOT/target/linux/rockchip/image/armv8.mk"
grep -q "define Device/nsy_g68-plus" "$IMG" && ok "Device/nsy_g68-plus" || bad "缺 Device 定义"
grep -q "TARGET_DEVICES += nsy_g68-plus" "$IMG" && ok "TARGET_DEVICES" || bad "缺 TARGET_DEVICES"
grep -q 'ROOTFS_DATA_PARTSIZE:-4096' "$ROOT/scripts/gen_image_generic.sh" && ok "rootfs_data 4096" || bad "rootfs_data 未设 4096"

echo
[ "$FAIL" -gt 0 ] && { echo "自检失败：$FAIL 项"; exit 1; }
echo "自检全部通过 ✅"

echo "== 4. 自定义 files/ =="
for f in usr/bin/bing-wallpaper usr/share/luci/menu.d/luci-app-bingwallpaper.json usr/share/rpcd/acl.d/luci-app-bingwallpaper.json www/luci-static/resources/view/bingwallpaper/bingwallpaper.js; do
	[ -s "$ROOT/files/$f" ] && ok "files/$f" || bad "缺 files/$f"
done
