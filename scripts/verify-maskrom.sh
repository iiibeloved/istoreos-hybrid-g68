#!/bin/sh
# =============================================================================
#  核心功能守卫：长按 Reset → MaskROM
#
#  任何构建（push / 定时 / 手动 / 任意 variant）都必须通过本脚本。
#  它检查三层，缺一即失败：
#    repo    : 投递方式只能是 overlay（不允许 u-boot patch 目录），且 overlay 四个文件含全部标记
#    applied : 应用到 iStoreOS 源码树后，$UB/src 下文件仍含标记（防被后续步骤覆盖）
#    built   : 编译产物 u-boot-rockchip.bin 含按键路径字符串，且 .config 的寄存器地址正确
#
#  用法：
#    verify-maskrom.sh <iStoreOS源码根目录> [--built]
# =============================================================================
set -eu
if [ "${1:-}" = "--repo" ]; then
	ROOT=""
	MODE="repo"
else
	ROOT="${1:?用法: verify-maskrom.sh <iStoreOS源码根目录>|--repo [--built]}"
	MODE="applied"
fi
[ "${2:-}" = "--built" ] && MODE="built"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
UB="${ROOT:+$ROOT/package/boot/uboot-rockchip}"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== [guard] 投递方式：overlay-only =="
if [ -d "$DEV/uboot/patches" ]; then bad "存在 device/uboot/patches（本项目规定只用 overlay，不允许 patch 投递）"; else ok "无 u-boot patch 目录"; fi
if [ -n "$ROOT" ]; then
	ls "$UB"/patches-* >/dev/null 2>&1 && bad "iStoreOS 树中出现 patches-*（patch 投递被启用）" || ok "iStoreOS 树无 patches-*"
fi

O="$DEV/uboot/overlay"
for f in arch/arm/mach-rockchip/boot_mode.c \
         arch/arm/mach-rockchip/Makefile \
         arch/arm/mach-rockchip/rk3568/rk3568.c \
         arch/arm/dts/Makefile; do
	[ -s "$O/$f" ] && ok "overlay: $f" || bad "缺 overlay: $f"
done
grep -q "set_back_to_bootrom_dnl_flag" "$O/arch/arm/mach-rockchip/boot_mode.c" && ok "boot_mode.c: 写 BROM 下载标志" || bad "boot_mode.c 缺 set_back_to_bootrom_dnl_flag"
grep -q "0xEF08A53C\|EF08A53C" "$O/arch/arm/mach-rockchip/boot_mode.c" && ok "boot_mode.c: BROM magic 0xEF08A53C" || bad "boot_mode.c 缺 magic"
grep -q "RK_DNL_ADC_CHAN" "$O/arch/arm/mach-rockchip/boot_mode.c" && ok "boot_mode.c: ADC 通道可覆盖(默认 0)" || bad "boot_mode.c 缺 RK_DNL_ADC_CHAN"
grep -q "0xfdc20200" "$O/arch/arm/mach-rockchip/boot_mode.c" && ok "boot_mode.c: 寄存器地址 0xfdc20200（自带兜底）" || bad "boot_mode.c 缺 0xfdc20200 兜底"
grep -q "spl_board_init" "$O/arch/arm/mach-rockchip/rk3568/rk3568.c" && ok "rk3568.c: spl_board_init" || bad "rk3568.c 缺 spl_board_init"
grep -q "setup_boot_mode" "$O/arch/arm/mach-rockchip/rk3568/rk3568.c" && ok "rk3568.c: 调 setup_boot_mode" || bad "rk3568.c 未调 setup_boot_mode"
grep -q "obj-y += boot_mode.o" "$O/arch/arm/mach-rockchip/Makefile" && ok "Makefile: boot_mode.o 编入 SPL" || bad "Makefile 未把 boot_mode.o 编入 SPL"
grep -q "rk3568-nsy-g68-plus.dtb" "$O/arch/arm/dts/Makefile" && ok "dts/Makefile: 登记 dtb" || bad "dts/Makefile 未登记 dtb"

echo "== [guard] 板级 defconfig（ADC/SPL/非 OF_UPSTREAM）=="
DEF="$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig"
for kv in "CONFIG_ADC=y" "CONFIG_SARADC_ROCKCHIP=y" "CONFIG_SPL_ADC=y" "CONFIG_ROCKCHIP_RK3568=y"; do
	grep -q "^$kv" "$DEF" && ok "defconfig: $kv" || bad "defconfig 缺 $kv"
done
grep -q "CONFIG_DEFAULT_DEVICE_TREE=\"rk3568-nsy-g68-plus\"" "$DEF" && ok "defconfig: 默认 DTS" || bad "defconfig 默认 DTS 不对"

if [ "$MODE" = "repo" ]; then
	echo
	[ "$FAIL" -gt 0 ] && { echo "核心功能守卫失败：$FAIL 项 —— overlay 内容不完整"; exit 1; }
	echo "核心功能守卫通过 ✅（repo 模式：overlay 内容完整）"
	exit 0
fi

echo "== [guard] 应用结果（$MODE）=="
for f in arch/arm/mach-rockchip/boot_mode.c arch/arm/mach-rockchip/rk3568/rk3568.c arch/arm/mach-rockchip/Makefile arch/arm/dts/Makefile; do
	[ -s "$UB/src/$f" ] && cmp -s "$O/$f" "$UB/src/$f" && ok "源码树 overlay 生效: $f" || bad "源码树 overlay 缺失/被改写: $f"
done
[ -s "$UB/src/arch/arm/dts/rk3568-nsy-g68-plus.dts" ] && ok "源码树板级 dts" || bad "源码树缺板级 dts"
[ -s "$UB/src/configs/nsy-g68-plus-rk3568_defconfig" ] && ok "源码树板级 defconfig" || bad "源码树缺板级 defconfig"

if [ "$MODE" = "built" ]; then
	echo "== [guard] 编译产物 =="
	BIN=$(find "$ROOT/build_dir" -name 'u-boot-rockchip.bin' -path '*nsy-g68-plus*' | head -1 || true)
	[ -n "$BIN" ] || BIN=$(find "$ROOT/staging_dir" -name 'nsy-g68-plus-rk3568-u-boot-rockchip.bin' | head -1 || true)
	if [ -n "$BIN" ]; then
		ok "产物: $BIN ($(stat -c%s "$BIN") 字节)"
		strings "$BIN" | grep -q "download key pressed" && ok "二进制含 download key pressed" || bad "二进制缺 download key pressed"
		strings "$BIN" | grep -q "adc_channel_single_shot" && ok "二进制含 adc_channel_single_shot" || bad "二进制缺 adc_channel_single_shot（ADC 未启用）"
	else
		bad "未找到 G68 的 u-boot-rockchip.bin"
	fi
	CFG=$(find "$ROOT/build_dir" -path '*u-boot-*/.config' | grep -E 'nsy-g68' | head -1 || true)
	[ -n "$CFG" ] || CFG=$(find "$ROOT/build_dir" -path '*u-boot-*/.config' | head -1 || true)
	if [ -n "$CFG" ]; then
		grep -q '^CONFIG_ROCKCHIP_BOOT_MODE_REG=0xfdc20200' "$CFG" && ok ".config: BOOT_MODE_REG=0xfdc20200" || bad ".config: BOOT_MODE_REG 不是 0xfdc20200"
		grep -q '^CONFIG_ADC=y' "$CFG" && ok ".config: CONFIG_ADC=y" || bad ".config: CONFIG_ADC 未启用"
	else
		bad "未找到 u-boot .config"
	fi
fi

echo
[ "$FAIL" -gt 0 ] && { echo "核心功能守卫失败：$FAIL 项 —— 长按 Reset→MaskROM 不可用，禁止继续构建"; exit 1; }
echo "核心功能守卫通过 ✅（长按 Reset→MaskROM 链路完整）"
