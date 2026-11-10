#!/bin/sh
# 构建前自检：检查设备层是否完整、注入是否生效、关键配置是否在
set -eu
ROOT="${1:?用法: selftest.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
UB="$ROOT/package/boot/uboot-rockchip"
IMG="$ROOT/target/linux/rockchip/image/armv8.mk"
KDTS="$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== 1. 文件存在性 =="
for f in "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus.dts" \
         "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus-u-boot.dtsi" \
         "$UB/src/configs/nsy-g68-plus-rk3568_defconfig" \
         "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" \
         "$UB/src/arch/arm/dts/Makefile" \
         "$KDTS"; do
	[ -s "$f" ] && ok "$(basename "$f")" || bad "缺失/为空: $f"
done

echo "== 2. u-boot 注入块 =="
n=$(grep -c "NSY-G68 long-press Reset -> MaskROM: begin" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" 2>/dev/null || echo 0)
[ "$n" = "1" ] && ok "注入块恰好 1 组" || bad "注入块数量=$n（应为 1）"
for sym in "spl_board_init" "rockchip_dnl_key_pressed" "0xEF08A53C" "0xfdc20200" "NSY_G68_DNL_ADC_CHAN"; do
	grep -q "$sym" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" && ok "包含 $sym" || bad "缺少 $sym"
done
grep -q "arch_cpu_init" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" && ok "上游 arch_cpu_init 保留" || bad "上游 arch_cpu_init 丢失（覆盖异常）"

echo "== 3. u-boot defconfig / dts / Makefile =="
DEF="$UB/src/configs/nsy-g68-plus-rk3568_defconfig"
grep -q "CONFIG_ROCKCHIP_RK3568=y" "$DEF" && ok "ROCKCHIP_RK3568" || bad "缺 CONFIG_ROCKCHIP_RK3568"
grep -q "# CONFIG_OF_UPSTREAM is not set" "$DEF" && ok "OF_UPSTREAM 关闭（用 arch/arm/dts）" || bad "OF_UPSTREAM 未关闭"
grep -q "CONFIG_DEFAULT_DEVICE_TREE=\"rk3568-nsy-g68-plus\"" "$DEF" && ok "默认 DTS" || bad "默认 DTS 不对"
grep -q "CONFIG_SPL_ADC=y" "$DEF" && ok "SPL_ADC" || bad "缺 SPL_ADC"
grep -q "rk3568-nsy-g68-plus.dtb" "$UB/src/arch/arm/dts/Makefile" && ok "dts Makefile 已登记 dtb" || bad "dts Makefile 未登记 dtb"
grep -q "U-Boot/nsy-g68-plus-rk3568" "$UB/Makefile" && ok "U-Boot 目标定义" || bad "缺 U-Boot/nsy-g68-plus-rk3568 定义"
sed -n '/^UBOOT_TARGETS/,/^$/p' "$UB/Makefile" | grep -q "nsy-g68-plus-rk3568" && ok "UBOOT_TARGETS 含目标" || bad "UBOOT_TARGETS 缺目标"

echo "== 4. u-boot DTS 关键节点 =="
for pat in "&saradc" "status = \"okay\"" "adc-keys" "saradc"; do
	grep -q "$pat" "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus.dts" && ok "u-boot dts: $pat" || bad "u-boot dts 缺 $pat"
done

echo "== 5. 内核 DTS =="
for pat in "adc-keys" "io-channels = <&saradc 0>" "&saradc" "recovery-key"; do
	grep -q "$pat" "$KDTS" && ok "kernel dts: $pat" || bad "kernel dts 缺 $pat"
done

echo "== 6. 镜像设备定义 =="
grep -q "define Device/nsy_g68-plus" "$IMG" && ok "Device/nsy_g68-plus" || bad "缺 Device/nsy_g68-plus"
grep -q "TARGET_DEVICES += nsy_g68-plus" "$IMG" && ok "TARGET_DEVICES 注册" || bad "缺 TARGET_DEVICES += nsy_g68-plus"
grep -q "UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568" "$IMG" && ok "UBOOT_DEVICE_NAME" || bad "缺 UBOOT_DEVICE_NAME"

echo
if [ "$FAIL" -gt 0 ]; then echo "自检失败：$FAIL 项"; exit 1; fi
echo "自检全部通过 ✅"
