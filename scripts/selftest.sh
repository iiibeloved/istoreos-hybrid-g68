#!/bin/sh
# 构建前自检（patch 投递方案）
set -eu
ROOT="${1:?用法: selftest.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
UB="$ROOT/package/boot/uboot-rockchip"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== 1. 版本守卫 =="
UV=$(sed -n 's/^PKG_VERSION:=//p' "$UB/Makefile" | head -1)
BASE=$(cat "$HERE/device/uboot/OVERLAY_BASE" 2>/dev/null || echo "")
[ "$UV" = "$BASE" ] && ok "u-boot 版本 $UV 与 patches 基准一致" || bad "u-boot=$UV 与 patches 基准=$BASE 不一致"

echo "== 2. u-boot 补丁（patch 101 等价，投递到 build_dir）=="
PATCHDIR="$DEV/uboot/patches"
[ -d "$PATCHDIR" ] || bad "缺少 $PATCHDIR"
PATCHFILES=$(ls "$PATCHDIR"/*.patch 2>/dev/null)
[ -n "$PATCHFILES" ] || bad "$PATCHDIR 为空（无补丁）"
for p in $PATCHFILES; do [ -s "$p" ] && ok "补丁存在: $(basename "$p")" || bad "空补丁: $(basename "$p")"; done
grep -q "rockchip_dnl_key_pressed"     $PATCHFILES && ok "补丁含 rockchip_dnl_key_pressed（按键检测）" || bad "补丁缺 rockchip_dnl_key_pressed"
grep -q "set_back_to_bootrom_dnl_flag" $PATCHFILES && ok "补丁含 set_back_to_bootrom_dnl_flag（进 MaskROM 路径）" || bad "补丁缺 set_back_to_bootrom_dnl_flag"
grep -q "spl_board_init"              $PATCHFILES && ok "补丁含 spl_board_init（SPL 调 setup_boot_mode）" || bad "补丁缺 spl_board_init"
grep -q "#ifndef CONFIG_ROCKCHIP_BOOT_MODE_REG" $PATCHFILES && ok "补丁含寄存器地址兜底 #ifndef → 0xfdc20200" || bad "补丁缺 #ifndef 兜底"
grep -q "CONFIG_ROCKCHIP_BOOT_MODE_REG=0xfdc20200" $PATCHFILES && ok "补丁含 defconfig 地址 0xfdc20200（设备实测）" || bad "补丁缺 0xfdc20200"
! grep -q "CONFIG_ROCKCHIP_BOOT_MODE_REG == 0" $PATCHFILES && ok "补丁未含 #if(==0) 空桩守卫" || bad "补丁仍含 #if(==0) 空桩（宏未设时=0，整段逻辑变空函数，静默失效）"
grep -q "boot_mode.o"                 $PATCHFILES && ok "补丁把 boot_mode.o 编入 SPL" || bad "补丁未把 boot_mode.o 编入 SPL"
# 若 apply-device 已把补丁拷到构建树，也确认一下
if [ -n "$UV" ] && [ -d "$UB/patches-$UV" ]; then
	ls "$UB/patches-$UV"/*.patch >/dev/null 2>&1 && ok "patches-$UV/ 已就绪（apply-device 已拷贝）" || bad "patches-$UV/ 缺失"
fi

echo "== 3. 板级文件（经补丁投递）=="
grep -q "nsy-g68-plus-rk3568_defconfig"      $PATCHFILES && ok "补丁含板级 defconfig" || bad "补丁缺板级 defconfig"
grep -q "rk3568-nsy-g68-plus.dts"            $PATCHFILES && ok "补丁含板级 dts" || bad "补丁缺板级 dts"
grep -q "rk3568-nsy-g68-plus-u-boot.dtsi"    $PATCHFILES && ok "补丁含板级 dtsi" || bad "补丁缺板级 dtsi"
KDTS="$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
[ -s "$KDTS" ] && ok "内核 dts 已放置" || bad "内核 dts 未放置（$KDTS）"

echo "== 4. 内核 DTS 关键节点 =="
for pat in "adc-keys" "io-channels = <&saradc 0>" "&saradc" "recovery-key"; do
	grep -q "$pat" "$KDTS" && ok "kernel dts: $pat" || bad "kernel dts 缺 $pat"
done
for pat in "&xpcs" "&rng"; do
	! grep -q "$pat" "$KDTS" && ok "kernel dts 未引用 mainline 不存在的 $pat" || bad "kernel dts 引用了 $pat（mainline 6.6 无此 label）"
done

echo "== 5. 构建系统插入 =="
grep -q "U-Boot/nsy-g68-plus-rk3568" "$UB/Makefile" && ok "U-Boot 目标定义" || bad "缺 U-Boot 目标定义"
sed -n '/^UBOOT_TARGETS/,/^$/p' "$UB/Makefile" | grep -q "nsy-g68-plus-rk3568" && ok "UBOOT_TARGETS 含目标" || bad "UBOOT_TARGETS 缺目标"
IMG="$ROOT/target/linux/rockchip/image/armv8.mk"
grep -q "define Device/nsy_g68-plus" "$IMG" && ok "Device/nsy_g68-plus" || bad "缺 Device/nsy_g68-plus"
grep -q "TARGET_DEVICES += nsy_g68-plus" "$IMG" && ok "TARGET_DEVICES 注册" || bad "缺 TARGET_DEVICES"
grep -q "UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568" "$IMG" && ok "UBOOT_DEVICE_NAME" || bad "缺 UBOOT_DEVICE_NAME"
grep -q 'ROOTFS_DATA_PARTSIZE:-4096' "$ROOT/scripts/gen_image_generic.sh" \
	&& ok "rootfs_data 默认 4096 MiB" || bad "gen_image_generic.sh 未把 rootfs_data 设为 4096"

echo "== 6. 内核补丁（XPCS / SGMII）=="
for prefix in 910 911 912 913; do
	if ls "$ROOT/target/linux/rockchip/patches-6.6/${prefix}-"*.patch >/dev/null 2>&1; then ok "内核补丁 ${prefix}-*"; else bad "缺内核补丁 ${prefix}-*"; fi
done

echo
[ "$FAIL" -gt 0 ] && { echo "自检失败：$FAIL 项"; exit 1; }
echo "自检全部通过 ✅"
