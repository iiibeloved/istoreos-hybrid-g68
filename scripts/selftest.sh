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
# 上游升级时板级文件必须保持库存版本（防止被上游同名文件覆盖而改变网络/maskrom 行为）
cmp -s "$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" "$KDTS" \
	&& ok "kernel dts 与库存逐字节一致" || bad "kernel dts 与库存不一致"
for f in rk3568-nsy-g68-plus.dts rk3568-nsy-g68-plus-u-boot.dtsi; do
	cmp -s "$DEV/uboot/static/$f" "$UB/src/arch/arm/dts/$f" \
		&& ok "uboot $f 与库存一致" || bad "uboot $f 不一致"
done
cmp -s "$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig" "$UB/src/configs/nsy-g68-plus-rk3568_defconfig" \
	&& ok "uboot defconfig 与库存一致" || bad "uboot defconfig 不一致"

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

echo "== 6. 交换机驱动（RTL8367S / swconfig 路线）=="
KCONF="$ROOT/target/linux/rockchip/armv8/config-6.6"
if [ -f "$KCONF" ]; then
	for sym in CONFIG_SWCONFIG CONFIG_RTL8366_SMI CONFIG_RTL8367B_PHY; do
		grep -qE "^$sym=[my]$" "$KCONF" && ok "内核配置 $sym" || bad "缺少内核配置 $sym"
	done
	# swconfig_leds.c 未处理 SWITCH_PORT_SPEED_2500，上游开 -Werror=switch 会编译失败
	if grep -qE '^CONFIG_SWCONFIG_LEDS=y$' "$KCONF"; then
		bad "config-6.6 仍开 CONFIG_SWCONFIG_LEDS=y（会触发 target/linux 编译失败）"
	elif grep -q '^# CONFIG_SWCONFIG_LEDS is not set' "$KCONF"; then
		ok "config-6.6 已关闭 SWCONFIG_LEDS"
	else
		bad "config-6.6 未显式关闭 SWCONFIG_LEDS（不确定状态）"
	fi
else
	bad "找不到 $KCONF"
fi
# apply-device.sh §7.54 必须已 patch 上游 netdevices.mk 的 CONFIG_SWCONFIG_LEDS=y → n
NMK="$ROOT/package/kernel/linux/modules/netdevices.mk"
if [ -f "$NMK" ]; then
	if grep -q 'CONFIG_SWCONFIG_LEDS=y' "$NMK" && ! grep -q 'CONFIG_SWCONFIG_LEDS=n' "$NMK"; then
		bad "netdevices.mk 的 CONFIG_SWCONFIG_LEDS 仍为 =y（apply-device 未执行 §7.54）"
	else
		ok "netdevices.mk 已关闭 SWCONFIG_LEDS（apply-device §7.54 生效）"
	fi
else
	bad "找不到 netdevices.mk"
fi
# 上游 generic/config-6.6 若强制 SWCONFIG_LEDS=y，kconfig.pl 合并时可能盖住我们的设置
GC="$ROOT/target/linux/generic/config-6.6"
if [ -f "$GC" ] && grep -qE '^CONFIG_SWCONFIG_LEDS=y$' "$GC"; then
	bad "上游 generic/config-6.6 强制 SWCONFIG_LEDS=y（kernel-config 可能被覆盖）"
else
	ok "上游 generic/config-6.6 未强制 SWCONFIG_LEDS=y"
fi
# 驱动 overlay 必须逐字节投递到 generic/files
for f in $(cd "$DEV/kernel-files/generic" && find . -type f | sed 's|^\./||'); do
	cmp -s "$DEV/kernel-files/generic/$f" "$ROOT/target/linux/generic/files/$f" \
		&& ok "kernel-files/$f" || bad "kernel-files/$f 未投递或内容不一致"
done
grep -q 'realtek,rtl8367s' "$DEV/kernel-files/generic/drivers/net/phy/rtl8367b.c" \
	&& ok "rtl8367b 驱动含 realtek,rtl8367s" || bad "rtl8367b 驱动缺 RTL8367S 支持"
for pkg in kmod-swconfig kmod-switch-rtl8366-smi kmod-switch-rtl8367b; do
	grep -qx "CONFIG_PACKAGE_$pkg=y" "$HERE/configs/g68-hybrid.config" \
		&& ok "包 $pkg" || bad "缺包 $pkg"
done

echo "== 7. 板级网络映射（独立 board.d，不依赖上游 02_network）=="
BDDST="$ROOT/target/linux/rockchip/armv8/base-files/etc/board.d/02_network_g68"
if [ -f "$BDDST" ]; then
	ok "board.d/02_network_g68 已投递"
	cmp -s "$DEV/board.d/02_network_g68" "$BDDST" && ok "映射内容一致" || bad "映射内容不一致"
	sh -n "$BDDST" && ok "映射脚本语法" || bad "映射脚本语法错误"
	grep -q 'nsy,g68-plus' "$BDDST" && ok "含 nsy,g68-plus 分支" || bad "缺 nsy,g68-plus 分支"
	if grep -q '6u@eth0' "$BDDST" && grep -q '7u@eth1' "$BDDST"; then
		ok "CPU 口映射 6u@eth0 / 7u@eth1"
	else
		bad "CPU 口映射缺失"
	fi
else
	bad "缺 board.d/02_network_g68"
fi
# 诊断版常驻脚本必须已移除（每次启动覆盖用户配置，且与 swconfig 映射冲突）
for f in files/etc/init.d/g68-network files/etc/init.d/g68-diag; do
	[ -e "$ROOT/$f" ] && bad "仍存在 $f（应已移除）" || ok "已移除 $f"
done

echo "== 8. 上游一致性（商城 / quickstart 以上游为准）=="
CFG="$HERE/configs/g68-hybrid.config"
for p in luci-app-store luci-app-quickstart quickstart; do
	grep -qx "CONFIG_PACKAGE_$p=y" "$CFG" && ok "选用上游包 $p" || bad "缺上游包 $p"
done
# 不允许本地固化商城/quickstart 的 LuCI 文件（必须随上游 feeds 变化）
OVR=$(cd "$DEV/files" && find . -type f \( -path '*luci*store*' -o -path '*luci*quickstart*' \) 2>/dev/null | head -5 || true)
[ -z "$OVR" ] && ok "无本地商城/quickstart 覆盖文件" || bad "存在本地覆盖: $OVR"
# i18n manifest 不应启用商城覆盖（注释行不计）
if grep -qE '^luci-app-store[[:space:]]' "$DEV/files/usr/share/g68/i18n-manifest" 2>/dev/null; then
	bad "i18n-manifest 仍启用商城覆盖"
else
	ok "i18n-manifest 未启用商城覆盖"
fi
# 上游跟随：upstream-watch 必须跟随 iStoreOS 分支并在变化时自动构建
grep -q 'ISTOREOS_BRANCH: istoreos-24.10' "$HERE/.github/workflows/upstream-watch.yml" \
	&& ok "upstream-watch 跟随 istoreos-24.10" || bad "upstream-watch 未跟随上游分支"
grep -q 'workflows/build.yml/dispatches' "$HERE/.github/workflows/upstream-watch.yml" \
	&& ok "上游变化自动触发构建" || bad "缺上游变化自动触发"

echo "== 9. quickstart / 网络向导 来源（官方 feeds 缺失 → small）=="
grep -q '^src-git small ' "$ROOT/feeds.conf" \
	&& ok "feeds.conf 已声明 small 源" || bad "feeds.conf 缺 small 源（quickstart/向导 config 项会被丢弃）"
for p in quickstart luci-app-quickstart luci-app-netwizard luci-app-store luci-app-alist luci-app-ddns-go; do
	grep -qx "CONFIG_PACKAGE_$p=y" "$CFG" && ok "已选 $p" || bad "缺少 $p"
done
# 官方 feeds 自身不得已含 quickstart；若上游将来内置，则应改回官方来源并撤掉 small
if [ -d "$ROOT/feeds" ]; then
	if grep -rqs 'PKG_NAME:=quickstart' "$ROOT/feeds" 2>/dev/null; then
		bad "官方 feeds 已提供 quickstart（small 来源需复核为重复）"
	else
		ok "官方 feeds 不含 quickstart（来源 = small）"
	fi
else
	printf '  [INFO] feeds 尚未 update，跳过官方 feeds 内容检查\n'
fi

if [ "$FAIL" -gt 0 ]; then
	echo "自检失败：$FAIL 项"
	exit 1
fi
echo "自检全部通过 ✅"
