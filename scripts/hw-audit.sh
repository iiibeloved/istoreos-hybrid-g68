#!/bin/sh
# =============================================================================
#  硬件级内容审核（编译前，prepare 阶段执行）
#
#  目的：避免「编译通过但真机不可用」。从 dts 提取硬件关键字，与
#  configs/g68-hybrid.config（软件包）、device/kernel-config（内核配置）、
#  device/uboot/static/*_defconfig（u-boot）交叉比对，输出：
#      已支持 / 缺失 / 显式豁免
#  关键项（DSA 交换机 / adc-keys / xpcs / 存储分区）缺失 → exit 1 阻断构建。
#
#  用法：hw-audit.sh [--warn-only]
# =============================================================================
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
CFG="$HERE/configs/g68-hybrid.config"
KCFG="$DEV/kernel-config"
EX="$DEV/hw-exemptions.txt"
DTS="$DEV/kernel-dts/rk3568-nsy-g68-plus.dts"
DEFCONFIG="$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig"
WARN_ONLY=0
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1

# 仓库内部分文件可能是 CRLF（u-boot defconfig 历史上就是），统一转 LF 后再比对
NORM="$(mktemp -d)"
trap 'rm -rf "$NORM"' EXIT
norm() { tr -d '\r' < "$1" > "$NORM/$(basename "$1")"; echo "$NORM/$(basename "$1")"; }
DTS=$(norm "$DTS")
CFG=$(norm "$CFG")
KCFG=$(norm "$KCFG")
DEFCONFIG=$(norm "$DEFCONFIG")

FAIL=0
WARN=0
ok()   { printf '  [SUPPORTED] %s\n' "$*"; }
miss() { printf '  [MISSING]   %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN]      %s\n' "$*"; WARN=$((WARN+1)); }
exm()  { printf '  [EXEMPT]    %s\n' "$*"; }

dts_has() { grep -qE "$1" "$DTS" 2>/dev/null; }
pkg_has() { grep -qE "^CONFIG_PACKAGE_$1=y$" "$CFG" 2>/dev/null; }
k_has()   { grep -qE "^$1=y$" "$KCFG" 2>/dev/null; }
exempted(){ [ -f "$EX" ] && grep -qiE "^$1[[:space:]]" "$EX"; }

# 可选：iStoreOS 源码树（prepare 阶段存在），用于读取内核版本与校验补丁一致性
ROOT="${HW_ROOT:-istoreos}"
KV=""
if [ -f "$ROOT/include/kernel-6.6" ]; then
	LV=$(sed -n 's/^LINUX_VERSION-6\.6 = //p' "$ROOT/include/kernel-6.6" | head -1)
	[ -n "$LV" ] && KV="6.6$LV"
fi
if [ -z "$KV" ]; then
	warn "未能读取 iStoreOS 内核版本（$ROOT/include/kernel-6.6），版本相关判定降级为警告"
fi
ver_ge() { [ -n "$KV" ] && awk -v a="$KV" -v b="$1" 'BEGIN{split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if(x[i]+0>y[i]+0)exit 0;if(x[i]+0<y[i]+0)exit 1}exit 0}'; }
patches_grep() { grep -lE "$1" "$DEV"/kernel-patches/*.patch 2>/dev/null || true; }


echo "== [hw-audit] 输入 =="
echo "  dts: $DTS"
echo "  config: $CFG ($(grep -c '^CONFIG_PACKAGE_.*=y$' "$CFG" 2>/dev/null || echo 0) 包)"
echo "  kernel-config: $KCFG"
echo

echo "== H3 交换机 RTL8367S (DSA) =="
if dts_has 'rtl8367s|realtek,mdio'; then
	if k_has CONFIG_NET_DSA_REALTEK_RTL8365MB && k_has CONFIG_NET_DSA_REALTEK_MDIO && k_has CONFIG_NET_DSA_TAG_RTL8_4; then
		ok "dts 声明 rtl8367s，kernel-config 已含 NET_DSA_REALTEK_* / TAG_RTL8_4"
	else
		miss "dts 声明 rtl8367s，但 kernel-config 缺 NET_DSA_REALTEK_RTL8365MB/MDIO/TAG_RTL8_4（LAN 将不可用）"
	fi
else
	warn "dts 未发现 rtl8367s 节点（若硬件实际存在需核查 dts）"
fi

echo "== H4 2.5G / XPCS =="
XPCS_PATCH=$(patches_grep 'xpcs')
if dts_has 'xpcs'; then
	if [ -n "$XPCS_PATCH" ]; then
		ok "dts 含 xpcs，补丁按内容命中: $(basename "$XPCS_PATCH" | head -1)"
	else
		miss "dts 含 xpcs，但 device/kernel-patches 中无含 xpcs 的补丁（内核不会生成 xpcs 节点）"
	fi
else
	warn "dts 未发现 xpcs 节点"
fi

# 历史事故：912-combphy 与 iStoreOS 6.6.144 冲突（hunk 1/4 FAILED），当时处理为「删除」而非修补。
# 若再次出现 combphy 补丁，且内核版本 >= 6.6.144，说明重复投递，必须拦截。
COMPHY_PATCH=$(patches_grep 'naneng-combphy')
if [ -n "$COMPHY_PATCH" ]; then
	if [ -n "$KV" ] && ver_ge 6.6.144; then
		miss "检测到 combphy 补丁（$(basename "$COMPHY_PATCH" | head -1)），但内核 $KV 已内置 sgmii-mac-sel 支持 → 会再次 hunk 冲突，应删除该补丁"
	else
		warn "检测到 combphy 补丁，当前内核版本 ${KV:-未知}，需确认不会与上游冲突"
	fi
else
	ok "无 combphy 补丁（符合 6.6.144 起「删除 912」的历史结论）"
fi

if dts_has 'sgmii-mac-sel'; then
	if [ -n "$(patches_grep 'sgmii-mac-sel')" ]; then
		ok "dts 使用 rockchip,sgmii-mac-sel，且由补丁提供"
	elif [ -n "$KV" ] && ver_ge 6.6.144; then
		ok "dts 使用 rockchip,sgmii-mac-sel，内核 $KV 已内置（无需补丁，912 已正确删除）"
	elif [ -n "$KV" ]; then
		miss "dts 使用 rockchip,sgmii-mac-sel，但内核 $KV < 6.6.144 且无补丁提供该属性"
	else
		warn "dts 使用 rockchip,sgmii-mac-sel，无法确认内核是否内置（版本未知）"
	fi
fi

echo "== H7 按键进 MaskROM (adc-keys) =="
if dts_has 'adc-keys|recovery-key'; then
	kbad=""
	grep -qE '^CONFIG_ADC=y$' "$DEFCONFIG" || kbad="$kbad ADC"
	grep -qE '^CONFIG_SARADC_ROCKCHIP=y$' "$DEFCONFIG" || kbad="$kbad SARADC_ROCKCHIP"
	grep -qE '^CONFIG_SPL_ADC=y$' "$DEFCONFIG" || kbad="$kbad SPL_ADC"
	[ -f "$DEV/uboot/overlay/arch/arm/mach-rockchip/boot_mode.c" ] || kbad="$kbad overlay/boot_mode.c"
	if [ -z "$kbad" ]; then
		ok "dts adc-keys + u-boot defconfig ADC/SARADC/SPL_ADC + overlay 齐全"
	else
		miss "MaskROM 链路缺:$kbad"
	fi
else
	miss "dts 缺 adc-keys/recovery-key（无法长按复位进 MaskROM）"
fi

echo "== H5 存储 / 分区 =="
if dts_has 'sdhci|sdmmc|mmc@'; then
	ok "dts 含 eMMC/SD 节点"
else
	warn "dts 未发现 mmc 节点"
fi
KP=$(grep -oE '^CONFIG_TARGET_KERNEL_PARTSIZE=[0-9]+' "$CFG" | head -1 | cut -d= -f2 || true)
RP=$(grep -oE '^CONFIG_TARGET_ROOTFS_PARTSIZE=[0-9]+' "$CFG" | head -1 | cut -d= -f2 || true)
if [ "${KP:-0}" -ge 16 ] 2>/dev/null && [ "${RP:-0}" -ge 200 ] 2>/dev/null; then
	ok "分区: kernel ${KP}MB / rootfs ${RP}MB"
else
	miss "分区异常: kernel=${KP:-未设}MB / rootfs=${RP:-未设}MB（需 kernel>=16, rootfs>=200）"
fi

echo "== H9 外设 ↔ 包（WiFi 显式豁免）=="
if dts_has 'mt7916|mt7915|mt76|wifi'; then
	if exempted mt7916 || exempted mt76 || exempted wifi; then
		exm "dts 声明 WiFi，按 device/hw-exemptions.txt 豁免（本设备不使用 WiFi）"
	elif pkg_has kmod-mt7915e || pkg_has kmod-mt7916-firmware; then
		ok "dts 声明 WiFi，且已选 mt76 驱动/固件"
	else
		warn "dts 声明 WiFi，但未选驱动且未登记豁免"
	fi
else
	exm "dts 未声明 WiFi（本设备不使用）"
fi
for pair in "usb3:kmod-usb3" "pcie:kmod-pci?"; do
	k=${pair%%:*}; p=${pair##*:}
	if dts_has "$k"; then
		if pkg_has "$p"; then ok "dts 含 $k，已选 $p"; else warn "dts 含 $k，未显式选 $p（内核可能内建，可忽略）"; fi
	fi
done

echo
echo "== [hw-audit] 汇总：缺失 $FAIL 项，警告 $WARN 项 =="
if [ "$FAIL" -gt 0 ]; then
	if [ "$WARN_ONLY" = "1" ]; then
		echo "::warning::硬件审核发现 $FAIL 项缺失（warn-only 模式不阻断）"
		exit 0
	fi
	echo "硬件审核未通过：请修复缺失项或在 device/hw-exemptions.txt 显式豁免"
	exit 1
fi
echo "硬件审核通过 ✅"
