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
if dts_has 'xpcs'; then
	if ls "$DEV"/kernel-patches/911-*.patch >/dev/null 2>&1; then
		ok "dts 含 xpcs，且存在 911 xpcs 补丁"
	else
		miss "dts 含 xpcs，但缺 device/kernel-patches/911-*.patch（内核不会生成 xpcs 节点）"
	fi
	if dts_has 'sgmii-mac-sel'; then
		warn "dts 使用 rockchip,sgmii-mac-sel —— 需确认当前内核驱动已内置该属性（iStoreOS 6.6.144 已含）"
	fi
else
	warn "dts 未发现 xpcs 节点"
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
