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
# 自动枚举：device/kernel-patches 下的每个补丁都必须被投递（增删补丁不再需要改自检）
for f in "$DEV"/kernel-patches/*.patch; do
	[ -f "$f" ] || continue
	base=$(basename "$f")
	ls "$ROOT/target/linux/rockchip/patches-6.6/$base" >/dev/null 2>&1 && ok "内核补丁 $base" || bad "缺内核补丁 $base"
done
# 关键功能补丁（XPCS / SGMII 2.5G / dwmac）必须存在
for p in 910 911 913; do
	ls "$ROOT/target/linux/rockchip/patches-6.6/${p}-"*.patch >/dev/null 2>&1 && ok "关键补丁 ${p}-*" || bad "缺关键补丁 ${p}-*"
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

echo "== 4. 自定义文件 / 中文覆盖投递 =="
if [ -d "$DEV/files" ]; then
	for f in $(cd "$DEV/files" && find . -type f | sed 's|^\./||'); do
		cmp -s "$DEV/files/$f" "$ROOT/files/$f" && ok "files/$f" || bad "files/$f 未投递或内容不一致"
	done
fi
if [ -d "$DEV/i18n-overlay" ]; then
	cnt=0
	for f in $(cd "$DEV/i18n-overlay" && find . -type f | sed 's|^\./||'); do
		cnt=$((cnt+1))
		cmp -s "$DEV/i18n-overlay/$f" "$ROOT/files/usr/share/g68/i18n-overlay/$f" && ok "i18n-overlay/$f" || bad "i18n-overlay/$f 未投递"
	done
	[ "$cnt" -gt 0 ] || bad "i18n-overlay 为空"
else
	bad "缺 device/i18n-overlay"
fi
# manifest 每行必须能找到对应 overlay 文件
while IFS=$(printf '\t') read -r pkg path; do
	case "$pkg" in ''|\#*) continue ;; esac
	[ -f "$DEV/i18n-overlay/$path" ] || bad "manifest 指向不存在的覆盖: $path"
done < "$DEV/i18n-manifest" 2>/dev/null || true

echo "== 6. 内核配置对齐（Realtek DSA / RTL8367S）=="
KCONF="$ROOT/target/linux/rockchip/armv8/config-6.6"
if [ -f "$KCONF" ]; then
	for sym in CONFIG_NET_DSA_REALTEK=y CONFIG_NET_DSA_REALTEK_MDIO=y CONFIG_NET_DSA_REALTEK_RTL8365MB=y CONFIG_NET_DSA_TAG_RTL8_4=y; do
		grep -qx "$sym" "$KCONF" && ok "内核配置 $sym" || bad "缺少内核配置 $sym"
	done
else
	bad "找不到 $KCONF"
fi
