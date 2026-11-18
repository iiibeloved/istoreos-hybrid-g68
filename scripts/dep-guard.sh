#!/bin/sh
# 编译前依赖版本一致性守卫（fail-fast，防上游 feed 漂移）
#
# 背景：small 等第三方 feed 跟随 upstream main，包版本约束会静默漂移。
# 2026-11-17 构建失败即因此：luci-app-homeproxy(20261111) 要求
# sing-box >= 1.15.0_alpha10，而官方 packages feed 提供 1.12.22 且被
# feeds install -a 先装占用同名链接，编译 3 小时后在 package/install 才报
# Error 255。修复：删官方链接、改从 small 装新版（见 build.yml）。
#
# 本脚本在 make defconfig 后、全量编译前运行：
#   1) 校验消费包声明的最低版本 <= 被依赖包实际生效版本
#   2) 确认 sing-box 生效链接确实来自 small（防官方旧版被误用）
# 消费包/被依赖包都来自 small，Makefile 直接从 feeds/small 读。
# 不满足立即失败，把漂移暴露在秒级而非小时级。
#
# 用法: sh scripts/dep-guard.sh <iStoreOS源码根目录>
set -u
ROOT="${1:?用法: dep-guard.sh <iStoreOS源码根目录>}"
FAIL=0
ok()  { printf '  [OK]   %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

# 版本敏感依赖对（此处为一组；如需扩展可复制本段）
CONSUMER="luci-app-homeproxy"
PROVIDER="sing-box"
CMF="$ROOT/feeds/small/$CONSUMER/Makefile"
PMF="$ROOT/feeds/small/$PROVIDER/Makefile"

# 从 Makefile 读版本（优先 PKG_UPSTREAM_VERSION，其次 PKG_VERSION）
read_version() {
	mf="$1"
	for key in PKG_UPSTREAM_VERSION PKG_VERSION; do
		v=$(sed -n "s/^${key}[?:]*=[[:space:]]*//p" "$mf" 2>/dev/null | head -1)
		[ -n "$v" ] && { echo "$v"; return 0; }
	done
	return 1
}

# 归一化分隔符后按 GNU 版本序比较：$1 >= $2 ?
norm() {
	echo "$1" | tr '[:upper:]' '[:lower:]' \
		| sed -E 's/-?(alpha|beta|rc)[._-]*/.\1./g; s/[_-]+/./g; s/\.\././g'
}
cmp_ge() {
	a=$(norm "$1"); b=$(norm "$2")
	[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -1)" = "$a" ] && return 0
	return 1
}

echo "== 依赖版本一致性守卫（编译前 fail-fast）=="

if [ ! -f "$CMF" ]; then
	bad "$CONSUMER Makefile 缺失: feeds/small/$CONSUMER/Makefile（feed 结构变化，需人工核对）"
elif [ ! -f "$PMF" ]; then
	bad "$PROVIDER Makefile 缺失: feeds/small/$PROVIDER/Makefile（feed 结构变化，需人工核对）"
else
	# 从消费包声明提取最低版本：sing-box (>=1.15.0_alpha10)
	req=$(grep -oE "${PROVIDER}[[:space:]]*\(>=[[:space:]]*[0-9][^)]*\)" "$CMF" 2>/dev/null \
		| head -1 | grep -oE '[0-9][^)]*' || true)
	have=$(read_version "$PMF" || true)
	echo "  $CONSUMER -> $PROVIDER : 要求 >= ${req:-<未声明>} ; 实际 ${have:-<未知>}"
	if [ -z "$req" ]; then
		bad "$CONSUMER 未找到 $PROVIDER 最低版本声明（约束格式变化，需人工核对）"
	elif [ -z "$have" ]; then
		bad "$PROVIDER 生效 Makefile 读不到版本"
	elif cmp_ge "$have" "$req"; then
		ok "$PROVIDER $have 满足 $CONSUMER 要求 >= $req"
	else
		bad "$PROVIDER $have 不满足 $CONSUMER 要求 >= $req（上游漂移）"
	fi
fi

# 生效链接校验：sing-box 必须由 small feed 提供（官方版本滞后是本次根因）
SB_LINK=$(readlink -f "$ROOT/package/feeds/small/sing-box" 2>/dev/null || true)
case "$SB_LINK" in
	*"feeds/small/"*) ok "sing-box 生效链接来自 small feed" ;;
	*) bad "sing-box 未从 small feed 生效（link=${SB_LINK:-<无>}）" ;;
esac

if [ "$FAIL" -gt 0 ]; then
	echo "::error::依赖版本一致性守卫失败：$FAIL 项，拒绝进入耗时编译"
	exit 1
fi
echo "依赖版本一致性守卫通过 ✅"
