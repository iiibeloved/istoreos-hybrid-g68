#!/bin/sh
# =============================================================================
#  核心网络功能包守卫（defconfig 后 + 最终 manifest，双阶段 fail-fast）
#
#  为什么需要两阶段：
#    selftest.sh / hw-audit.sh 只检查 configs/g68-hybrid.config 这个"输入"，
#    但真正的包集由 make defconfig 展开，上游 feed 漂移可能让关键包被静默丢弃。
#    历史上的 LAN 拿不到 IP 就是因为用户态 swconfig 未进入最终镜像。
#    因此：
#      config  <defconfig文件>   —— build 作业 make defconfig 之后立即断言，
#                                   缺关键包则秒级失败，不浪费 5 小时编译；
#      manifest <manifest文件>  —— 编译产物阶段再断言一次，确保最终镜像确实含包，
#                                   缺任一包则禁止发布 Release。
#
#  关键包清单（网络生命线，缺一不可）：
#    swconfig                 用户态工具，安装 /lib/network/switch.sh 应用 UCI VLAN
#    kmod-swconfig            内核 swconfig 框架
#    kmod-switch-rtl8366-smi  MDIO 总线驱动（与 RTL8367S 通信）
#    kmod-switch-rtl8367b     RTL8367S 交换机芯片驱动
#    dnsmasq-full             LAN DHCP 服务端（与 dnsmasq 互斥）
#
#  用法：verify-critical.sh config <.config> | verify-critical.sh manifest <manifest>
# =============================================================================
set -eu
MODE="${1:?用法: verify-critical.sh config|<manifest> <文件>}"
FILE="${2:?用法: verify-critical.sh config|<manifest> <文件>}"
[ -f "$FILE" ] || { echo "::error::关键包守卫: 文件不存在 $FILE"; exit 1; }

CRIT="swconfig kmod-swconfig kmod-switch-rtl8366-smi kmod-switch-rtl8367b dnsmasq-full"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "== [guard] 核心网络功能包（$MODE: $FILE）=="
for p in $CRIT; do
	case "$MODE" in
		config)   pat="^CONFIG_PACKAGE_${p}=y$" ;;
		manifest) pat="^${p} - " ;;
		*) echo "::error::未知模式 $MODE（应为 config 或 manifest）" >&2; exit 2 ;;
	esac
	if grep -qE "$pat" "$FILE"; then
		ok "$p"
	else
		bad "缺关键包 $p（网络/DHCP 将不可用，禁止继续）"
	fi
done

if [ "$MODE" = "config" ]; then
	if grep -qE '^CONFIG_PACKAGE_dnsmasq=y$' "$FILE"; then
		bad "dnsmasq 与 dnsmasq-full 同时选中（PROVIDES 同名，必须互斥）"
	else
		ok "dnsmasq 未与 dnsmasq-full 冲突"
	fi
fi

echo
if [ "$FAIL" -gt 0 ]; then
	echo "::error::核心网络包守卫失败：$FAIL 项 —— 禁止继续构建/发布"
	exit 1
fi
echo "核心网络包守卫通过 ✅（LAN/WAN/DHCP 生命线齐全）"
