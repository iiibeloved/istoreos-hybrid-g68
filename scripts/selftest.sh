#!/bin/sh
# 构建前自检（overlay 方案）
set -eu
ROOT="${1:?用法: selftest.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
UB="$ROOT/package/boot/uboot-rockchip"
IMG="$ROOT/target/linux/rockchip/image/armv8.mk"
KDTS="$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== 1. 版本守卫 =="
UV=$(sed -n 's/^PKG_VERSION:=//p' "$UB/Makefile" | head -1)
BASE=$(cat "$HERE/device/uboot/OVERLAY_BASE" 2>/dev/null || echo "")
[ "$UV" = "$BASE" ] && ok "u-boot 版本 $UV 与 overlay 基准一致" || bad "u-boot=$UV 与 overlay 基准=$BASE 不一致"

echo "== 2. overlay 文件（上游改动用已验证完整文件覆盖）=="
for f in arch/arm/mach-rockchip/Makefile \
         arch/arm/mach-rockchip/boot_mode.c \
         arch/arm/mach-rockchip/rk3568/rk3568.c \
         arch/arm/dts/Makefile; do
	[ -s "$UB/src/$f" ] && ok "覆盖: $f" || bad "缺覆盖文件: $f"
done
grep -q "RK_DNL_ADC_CHAN" "$UB/src/arch/arm/mach-rockchip/boot_mode.c" && ok "boot_mode.c: ADC 通道可覆盖(默认0)" || bad "boot_mode.c 未含 RK_DNL_ADC_CHAN"
grep -q "spl_board_init" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" && ok "rk3568.c: spl_board_init()" || bad "rk3568.c 缺 spl_board_init()"
grep -q "obj-y += boot_mode.o" "$UB/src/arch/arm/mach-rockchip/Makefile" && ok "Makefile: boot_mode.o 编入 SPL" || bad "Makefile 未把 boot_mode.o 编入 SPL"
grep -q "rk3568-nsy-g68-plus.dtb" "$UB/src/arch/arm/dts/Makefile" && ok "dts/Makefile: 登记 dtb" || bad "dts/Makefile 未登记 dtb"

echo "== 3. 板级文件 =="
for f in "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus.dts" \
         "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus-u-boot.dtsi" \
         "$UB/src/configs/nsy-g68-plus-rk3568_defconfig" \
         "$KDTS"; do
	[ -s "$f" ] && ok "$(basename "$f")" || bad "缺失/为空: $f"
done

echo "== 4. u-boot defconfig 关键项 =="
DEF="$UB/src/configs/nsy-g68-plus-rk3568_defconfig"
for sym in "CONFIG_ROCKCHIP_RK3568=y" "CONFIG_ADC=y" "CONFIG_SARADC_ROCKCHIP=y" \
           "CONFIG_CMD_ADC=y" "CONFIG_SPL_ADC=y"; do
	grep -q "^$sym" "$DEF" && ok "$sym" || bad "缺 $sym"
done
grep -q '# CONFIG_OF_UPSTREAM is not set' "$DEF" && ok "OF_UPSTREAM 关闭（用 arch/arm/dts）" || bad "OF_UPSTREAM 未关闭"

echo "== 5. u-boot DTS =="
for pat in "&saradc" "adc-keys" "saradc"; do
	grep -q "$pat" "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus.dts" && ok "u-boot dts: $pat" || bad "u-boot dts 缺 $pat"
done

echo "== 6. 内核 DTS =="
for pat in "adc-keys" "io-channels = <&saradc 0>" "&saradc" "recovery-key"; do
	grep -q "$pat" "$KDTS" && ok "kernel dts: $pat" || bad "kernel dts 缺 $pat"
done

echo "== 7. 构建系统插入 =="
grep -q "U-Boot/nsy-g68-plus-rk3568" "$UB/Makefile" && ok "U-Boot 目标定义" || bad "缺 U-Boot 目标定义"
sed -n '/^UBOOT_TARGETS/,/^$/p' "$UB/Makefile" | grep -q "nsy-g68-plus-rk3568" && ok "UBOOT_TARGETS 含目标" || bad "UBOOT_TARGETS 缺目标"
grep -q "define Device/nsy_g68-plus" "$IMG" && ok "Device/nsy_g68-plus" || bad "缺 Device/nsy_g68-plus"
grep -q "TARGET_DEVICES += nsy_g68-plus" "$IMG" && ok "TARGET_DEVICES 注册" || bad "缺 TARGET_DEVICES"
grep -q "UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568" "$IMG" && ok "UBOOT_DEVICE_NAME" || bad "缺 UBOOT_DEVICE_NAME"

echo
[ "$FAIL" -gt 0 ] && { echo "自检失败：$FAIL 项"; exit 1; }
echo "自检全部通过 ✅"

echo "== 8. 内核补丁（XPCS / SGMII）=="
for prefix in 910 911 912 913; do
	if ls "$ROOT/target/linux/rockchip/patches-6.6/${prefix}-"*.patch >/dev/null 2>&1; then ok "内核补丁 ${prefix}-*"; else bad "缺内核补丁 ${prefix}-*"; fi
done
grep -q "xpcs" "$KDTS" && ok "DTS 使用 xpcs（需补丁支持）" || true
