#!/bin/sh
# =============================================================================
#  网络链路"应用后"守卫（编译后、发布前，针对上游增量变化）
#
#  为什么需要这一层：
#    selftest §2 只确认内核补丁"被投递"到 patches-6.6/ 目录（ls），
#    hw-audit 只做 dts↔config↔补丁内容的静态交叉核对。
#    但补丁是文本 diff —— 上游 iStoreOS 每次增量提交都可能改动
#    dwmac-rk.c / rk3568 原生 dts 的上下文，使 hunk 静默 FAILED。
#    历史事故 c6d9bc6：915 补丁 hunk 失败 → 编译仍"成功" → 刷入后
#    LAN 全瘫、仅硬件交换（拿不到 IP）。这类"编译通过但网络死"无法被
#    包级守卫（verify-critical）发现，因为包都齐全。
#
#  本脚本在 make 之后检查"打过补丁的内核源码"与"已投递的板级 DTS"：
#    source  <内核源码树>   —— dwmac-rk.c 必须含 910/913/915 的应用后代码；
#                              若 hunk 漂移未应用，这里立刻失败，禁止发布。
#    dts     <板级 DTS>     —— 必须含 915 生效所需的 pipegrf phandle +
#                              sgmii-mac-sel 属性（上游同名 dts 覆盖会破坏）。
#
#  用法：
#    verify-network.sh source <linux-6.6.x 源码树根>
#    verify-network.sh dts    <rk3568-nsy-g68-plus.dts>
# =============================================================================
set -eu
MODE="${1:?用法: verify-network.sh source|dts <文件/目录>}"
TARGET="${2:?用法: verify-network.sh source|dts <文件/目录>}"

FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

need() { # need <文件> <描述> <正则>
	if grep -qE "$3" "$1" 2>/dev/null; then ok "$2"; else bad "$2 —— 缺锚点 / 补丁未生效: $3"; fi
}

case "$MODE" in
	source)
		[ -d "$TARGET" ] || { echo "::error::内核源码树不存在: $TARGET"; exit 1; }
		DW="$TARGET/drivers/net/ethernet/stmicro/stmmac/dwmac-rk.c"
		[ -f "$DW" ] || { echo "::error::找不到打补丁后的 dwmac-rk.c: $DW"; exit 1; }
		echo "== [network-guard] 编译后内核源码网络补丁（$DW）=="
		# 910：stmmac 的 SGMII/QSGMII 支持（set_to_sgmii 函数指针）
		need "$DW" "910 SGMII 支持函数指针 set_to_sgmii" 'set_to_sgmii'
		# 913：fixed-link 场景不跑 XPCS 自协商（2.5G/1G fixed-link 必需）
		need "$DW" "913 fixed-link 处理 is_fixed_link" 'is_fixed_link'
		need "$DW" "913 fixed-link 强制 1000Mbps BMCR_SPEED1000" 'BMCR_SPEED1000'
		# 915：SGMII MAC select 编程（LAN 拿不到 IP 的根因修复，三个 hunk 缺一不可）
		need "$DW" "915 pipe_grf 成员" 'struct regmap \*pipe_grf'
		need "$DW" "915 PIPE_GRF_XPCS MAC select 编程" 'RK3568_PIPE_GRF_XPCS_SGMII_MAC_SEL'
		need "$DW" "915 pipegrf phandle 读取" 'rockchip,pipegrf'
		# RTL8367S 驱动 overlay（整文件覆盖，含 realtek,rtl8367s）
		PHY="$TARGET/drivers/net/phy/rtl8367b.c"
		if [ -f "$PHY" ]; then
			need "$PHY" "RTL8367S 驱动 overlay 已生效" 'realtek,rtl8367s'
		else
			bad "找不到打补丁后的 rtl8367b.c: $PHY"
		fi
		;;
	dts)
		[ -f "$TARGET" ] || { echo "::error::DTS 文件不存在: $TARGET"; exit 1; }
		echo "== [network-guard] 板级 DTS 网络节点（$TARGET）=="
		# 915 生效的两个必要条件：GMAC1 的 sgmii-mac-sel 属性 + pipegrf phandle
		need "$TARGET" "DTS GMAC1 sgmii-mac-sel 属性" 'rockchip,sgmii-mac-sel'
		need "$TARGET" "DTS GMAC1 pipegrf phandle（915 编程 PIPE_GRF 所需）" 'rockchip,pipegrf'
		need "$TARGET" "DTS GMAC1 SGMII phy-mode" 'phy-mode = "sgmii"'
		need "$TARGET" "DTS xpcs 节点（XPCS 补丁消费）" '&xpcs'
		# RTL8367S switch 节点（若上游 dts 结构变化丢失，交换芯片不识别）
		need "$TARGET" "DTS RTL8367S 交换机节点" 'rtl8367s'
		;;
	*)
		echo "::error::未知模式 $MODE（应为 source 或 dts）" >&2
		exit 2
		;;
esac

echo
if [ "$FAIL" -gt 0 ]; then
	echo "::error::网络链路应用后守卫失败：$FAIL 项 —— 禁止发布（上游增量可能已让 LAN/WAN 失效）"
	exit 1
fi
echo "网络链路应用后守卫通过 ✅（补丁已生效 / DTS 网络节点完整）"
