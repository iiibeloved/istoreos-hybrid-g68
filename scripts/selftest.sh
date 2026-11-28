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

echo "== 0.5 文本文件行尾守卫（CRLF 会让 sh / grep -qx / make defconfig 静默失效）=="
# 历史事故：configs/g68-hybrid.config 曾被写成 CRLF，使包集自检全项误报；
# scripts/dep-guard.sh 被写成 CRLF 时，dash 把 `set -u\r` 当成非法选项直接退出。
# 这里在自检最前端统一拦截，避免同类漂移再进入耗时编译。
CRCH=$(printf '\r')
EOL_N=0
for f in "$HERE"/scripts/*.sh "$HERE"/configs/*.config "$HERE"/.github/workflows/*.yml \
         "$HERE"/device/files/usr/bin/* "$HERE"/device/files/etc/uci-defaults/*; do
	[ -f "$f" ] || continue
	EOL_N=$((EOL_N + 1))
	if grep -q "$CRCH" "$f"; then
		bad "$f 含 CRLF 行尾（必须 LF）"
	fi
done
ok "已检查 $EOL_N 个文本文件行尾"

echo "== 1. 内核 DTS 关键节点 =="
KDTS="$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/rk3568-nsy-g68-plus.dts"
for pat in "adc-keys" "io-channels = <&saradc 0>" "&saradc" "recovery-key" "&xpcs"; do
	grep -q "$pat" "$KDTS" 2>/dev/null && ok "kernel dts: $pat" || bad "kernel dts 缺 $pat"
done
# 复位键系统内恢复出厂：adc-keys 必须映射 KEY_RESTART。
# KEY_F12 不在 button-hotplug 映射表内，会导致系统运行时按复位键无任何效果。
grep -q 'linux,code = <KEY_RESTART>' "$KDTS" 2>/dev/null \
	&& ok "kernel dts: 复位键映射 KEY_RESTART（长按可恢复出厂）" \
	|| bad "kernel dts 复位键未映射 KEY_RESTART（系统内复位键失效）"
! grep -q 'linux,code = <KEY_F12>' "$KDTS" 2>/dev/null \
	&& ok "kernel dts: 无 KEY_F12 残留" \
	|| bad "kernel dts 仍有 KEY_F12（button-hotplug 不识别）"
# 复位键驱动链：SARADC kmod 必须打包，否则 adc-keys 永远 deferred probe、复位键失效。
grep -q '^CONFIG_PACKAGE_kmod-iio-rockchip-saradc=y' "$DEV/configs/"*.config 2>/dev/null \
	&& ok "config: SARADC kmod 已启用（adc-keys 可得 io-channel）" \
	|| bad "config 缺 kmod-iio-rockchip-saradc（复位键驱动链断裂）"
# 上游升级时板级文件必须保持库存版本（防止被上游同名文件覆盖而改变网络/maskrom 行为）
cmp -s "$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" "$KDTS" \
	&& ok "kernel dts 与库存逐字节一致" || bad "kernel dts 与库存不一致"
# 网络链路 DTS 锚点（915 生效所需 pipegrf phandle + sgmii-mac-sel + RTL8367S 节点）
# 逐字节比对只保证"投递的=库存的"，无法保证"库存内容本身正确"。这里校验锚点，
# 防止上游同名 dts 结构变化或维护时误删关键节点导致编译成功但 LAN 全瘫。
if [ -s "$HERE/scripts/verify-network.sh" ]; then
	sh "$HERE/scripts/verify-network.sh" dts "$KDTS" || FAIL=$((FAIL+1))
else
	bad "缺 verify-network.sh（网络链路应用后守卫）"
fi
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
for p in 910 911 913 915; do
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
# swconfig 用户态工具是 VLAN 分组生效的必要条件，内核 kmod 无法替代；
# 缺它则 LAN 口桥接建不起来（真机拿不到 IP），必须一并断言。
for pkg in swconfig kmod-swconfig kmod-switch-rtl8366-smi kmod-switch-rtl8367b; do
	grep -qx "CONFIG_PACKAGE_$pkg=y" "$HERE/configs/g68-hybrid.config" \
		&& ok "包 $pkg" || bad "缺包 $pkg"
done
# 核心网络包守卫脚本必须存在，且 build.yml 必须在 defconfig 后与 manifest 阶段各调用一次；
# 防止上游更新/误操作把这道 fail-fast 守卫摘掉后，包漂移无人拦截。
[ -s "$HERE/scripts/verify-critical.sh" ] \
	&& ok "verify-critical.sh 存在" || bad "缺 verify-critical.sh（网络包 fail-fast 守卫）"
[ "$(grep -c 'verify-critical.sh config' "$HERE/.github/workflows/build.yml")" -ge 1 ] \
	&& ok "build.yml 已挂 defconfig 后守卫" || bad "build.yml 缺 defconfig 后网络包守卫"
[ "$(grep -c 'verify-critical.sh manifest' "$HERE/.github/workflows/build.yml")" -ge 1 ] \
	&& ok "build.yml 已挂 manifest 守卫" || bad "build.yml 缺 manifest 网络包守卫"
# 应用后网络守卫：脚本存在 + build.yml 在编译产物阶段挂载 source 检查，防被误摘。
[ -s "$HERE/scripts/verify-network.sh" ] \
	&& ok "verify-network.sh 存在" || bad "缺 verify-network.sh（网络应用后守卫）"
[ "$(grep -c 'verify-network.sh source' "$HERE/.github/workflows/build.yml")" -ge 1 ] \
	&& ok "build.yml 已挂编译后网络应用守卫" || bad "build.yml 缺编译后网络应用守卫（补丁 hunk 漂移无人拦截）"

echo "== 7. 板级网络映射（独立 board.d，不依赖上游 02_network）=="
BDDST="$ROOT/target/linux/rockchip/armv8/base-files/etc/board.d/02_network_g68"
if [ -f "$BDDST" ]; then
	ok "board.d/02_network_g68 已投递"
	cmp -s "$DEV/board.d/02_network_g68" "$BDDST" && ok "映射内容一致" || bad "映射内容不一致"
	sh -n "$BDDST" && ok "映射脚本语法" || bad "映射脚本语法错误"
	grep -q 'nsy,g68-plus' "$BDDST" && ok "含 nsy,g68-plus 分支" || bad "缺 nsy,g68-plus 分支"
	# 不断言具体端口编号（6/7 可随硬件/真机复核调整），只守住「有两条 untagged CPU 上联分别挂 eth0/eth1」；
	# 映射内容本身已由上面的 cmp -s 与仓库基线 device/board.d/02_network_g68 逐字比对锁定。
	if grep -qE '[0-9]+u@eth0' "$BDDST" && grep -qE '[0-9]+u@eth1' "$BDDST" \
	   && [ "$(grep -oE '[0-9]+:lan' "$BDDST" | wc -l)" -ge 1 ] \
	   && grep -qE '[0-9]+:wan' "$BDDST"; then
		ok "CPU 双上联映射存在（$(grep -oE '[0-9]+u@eth[01]' "$BDDST" | tr '\n' ' ')）+ LAN/WAN 端口齐备"
	else
		bad "CPU 上联映射或 LAN/WAN 端口缺失"
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
for p in quickstart luci-app-quickstart luci-app-store luci-app-ddns-go; do
	grep -qx "CONFIG_PACKAGE_$p=y" "$CFG" && ok "已选 $p" || bad "缺少 $p"
done
grep -qx 'CONFIG_PACKAGE_luci-app-netwizard=y' "$CFG" \
	&& bad "设置向导（luci-app-netwizard）仍启用" || ok "设置向导已移除"
grep -qx 'CONFIG_PACKAGE_luci-mod-dashboard=y' "$CFG" \
	&& bad "管理面板（luci-mod-dashboard）仍启用" || ok "管理面板已移除"
# 官方 feeds 自身不得已含 quickstart；若上游将来内置，则应改回官方来源并撤掉 small
# 注意：只查官方 feed 目录，排除 small 自身，否则会把 small 当成官方来源
if [ -d "$ROOT/feeds" ]; then
	FOUND=""
	for d in packages luci store third routing telephony; do
		[ -d "$ROOT/feeds/$d" ] || continue
		grep -rqs 'PKG_NAME:=quickstart' "$ROOT/feeds/$d" && FOUND="$d"
	done
	if [ -n "$FOUND" ]; then
		bad "官方 feeds（$FOUND）已提供 quickstart（small 来源需复核为重复）"
	else
		ok "官方 feeds 不含 quickstart（来源 = small）"
	fi
else
	printf '  [INFO] feeds 尚未 update，跳过官方 feeds 内容检查\n'
fi

echo "== 10. DNS 替换：dnsmasq-full 取代上游 dnsmasq（去重规则唯一例外）=="
grep -qx 'CONFIG_PACKAGE_dnsmasq-full=y' "$CFG" && ok "已选 dnsmasq-full" || bad "缺少 dnsmasq-full"
grep -qx '# CONFIG_PACKAGE_dnsmasq is not set' "$CFG" \
	&& ok "显式关闭上游 dnsmasq" || bad "缺 '# CONFIG_PACKAGE_dnsmasq is not set'（两者互斥）"
if grep -qx 'CONFIG_PACKAGE_dnsmasq=y' "$CFG"; then
	bad "同时选中 dnsmasq（PROVIDES 同名，必须排除）"
else
	ok "configs 未选中上游 dnsmasq"
fi
grep -q -- '--allow dnsmasq-full' "$HERE/.github/workflows/build.yml" \
	&& ok "package-guard 已豁免 dnsmasq-full" || bad "package-guard 缺 --allow dnsmasq-full"

echo "== 11. 代理应用（openclash / passwall / homeproxy）=="
for p in luci-app-openclash luci-app-passwall luci-app-homeproxy; do
	grep -qx "CONFIG_PACKAGE_$p=y" "$CFG" && ok "已选 $p" || bad "缺少 $p"
done
for i in INCLUDE_Xray INCLUDE_SingBox INCLUDE_Geoview; do
	grep -qx "CONFIG_PACKAGE_luci-app-passwall_$i=y" "$CFG" \
		&& ok "passwall $i" || bad "passwall $i 未选（passwall 会缺核心）"
done

echo "== 12. Go 工具链放宽（small 的 Go 包要求 go>=1.25）=="
grep -q 'GOTOOLCHAIN=local/GOTOOLCHAIN=auto' "$HERE/.github/workflows/build.yml" \
	&& ok "build.yml 已把 GOTOOLCHAIN 改为 auto" \
	|| bad "build.yml 未放宽 GOTOOLCHAIN（xray/sing-box/ddns-go 会编译失败）"

echo "== 13. 服务菜单：隐藏顶级 Modem + Samba4 标签（纵深防御）=="
# 主动防线已在编译期禁用整个蜂窝栈（见 §14 / verify-critical）。
# 本节的 menu.d 覆盖 + sms.lua entry 注释是纵深兜底：即便上游意外带回
# luci-app-sms-tool，Modem 菜单也不会露出。两者都保留，不冲突。
# 顶级 Modem 来自 luci-app-sms-tool 的 controller entry({"admin","modem"},...)，
# 与 zz-hide-modem.json 原覆盖的 admin/status/modemmanager 不是同一节点。
# 真机实测：仅 menu.d 覆盖会被 controller 重算为 satisfied=true（仍显示）；
# 必须「注释 sms.lua 顶级 entry + menu.d 恒假覆盖 admin/modem」两者配合。
HIDE_JSON="$DEV/files/usr/share/luci/menu.d/zz-hide-modem.json"
HIDE_ENTRY="$DEV/files/etc/uci-defaults/91-g68-hide-modem-entry"
SAMBA_JSON="$DEV/files/usr/share/luci/menu.d/zz-samba4-label.json"
[ -f "$HIDE_JSON" ] && ok "zz-hide-modem.json 存在" || bad "缺 zz-hide-modem.json"
grep -q 'admin/status/modemmanager' "$HIDE_JSON" 2>/dev/null \
	&& ok "覆盖 Cellular Network 节点" || bad "zz-hide-modem.json 缺 admin/status/modemmanager"
grep -q 'admin/modem' "$HIDE_JSON" 2>/dev/null \
	&& ok "覆盖顶级 Modem 节点 admin/modem" || bad "zz-hide-modem.json 缺 admin/modem（顶级 Modem 会显示）"
[ -f "$HIDE_ENTRY" ] && ok "91-g68-hide-modem-entry 存在" || bad "缺 91-g68-hide-modem-entry（controller 会重算覆盖）"
grep -q 'entry({"admin", "modem"}, firstchild()' "$HIDE_ENTRY" 2>/dev/null \
	&& ok "脚本含 sms.lua 顶级 entry 注释规则" || bad "隐藏脚本缺 sms.lua entry 处理"
grep -q 'G68-HIDDEN' "$HIDE_ENTRY" 2>/dev/null \
	&& ok "隐藏脚本用 G68-HIDDEN 标记（幂等）" || bad "隐藏脚本缺 G68-HIDDEN 幂等标记"
# Samba4 标签：两个"网络共享"要可区分，只改 samba4（ksmbd 保持原名）
[ -f "$SAMBA_JSON" ] && ok "zz-samba4-label.json 存在" || bad "缺 zz-samba4-label.json"
grep -q 'admin/services/samba4' "$SAMBA_JSON" 2>/dev/null \
	&& ok "覆盖 Samba4 菜单节点" || bad "zz-samba4-label.json 缺 admin/services/samba4"
grep -q '网络共享++' "$SAMBA_JSON" 2>/dev/null \
	&& ok "Samba4 标签=网络共享++（与 ksmbd 区分）" || bad "Samba4 标签未设为网络共享++"

echo "== 14. 编译期蜂窝能力整体移除（主动防线，fail-fast）=="
# 复用 verify-critical 的 config 守卫：既查网络生命线齐全，又查 32 个蜂窝包
# 全部为 'is not set'、且 SMSC 以太网 PHY 驱动仍保留。清单只在 verify-critical
# 维护一份，避免两处漂移。上游/去重把任一蜂窝包带回即在此失败。
sh "$HERE/scripts/verify-critical.sh" config "$CFG" || FAIL=$((FAIL+1))

if [ "$FAIL" -gt 0 ]; then
	echo "自检失败：$FAIL 项"
	exit 1
fi
echo "自检全部通过 ✅"
