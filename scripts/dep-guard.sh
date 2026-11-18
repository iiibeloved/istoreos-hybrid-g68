#!/bin/sh
# 通用依赖版本一致性守卫（fail-fast，防 feed 漂移）
#
# 用法: sh scripts/dep-guard.sh <iStoreOS源码根目录> [feed-precedence.txt]
# 默认优先级文件: <源码根>/../configs/feed-precedence.txt
#
# 做什么:
#   1. 读取 make defconfig 后的 .config，遍历所有 CONFIG_PACKAGE_*-y 的包
#   2. 从这些包的 Makefile 中提取带版本号的依赖声明
#   3. 解析被依赖包的实际生效版本并比较，不满足立即失败
#   4. 校验 feed-precedence.txt 中声明的同名包来源优先级
#
# 支持比较符: >= > <= < = !=
# 动态版本片段 $(...) 会告警跳过，需人工核对；不会静默放行。
set -u

ROOT="${1:?用法: dep-guard.sh <iStoreOS源码根目录> [precedence-file]}"
PREC="${2:-$ROOT/../configs/feed-precedence.txt}"
CONFIG="$ROOT/.config"

FAIL=0
WARN=0
TMP_SEL="/tmp/dep-guard-sel.$$"
TMP_CON="/tmp/dep-guard-con.$$"
TMP_CON2="/tmp/dep-guard-con2.$$"
cleanup() { rm -f "$TMP_SEL" "$TMP_CON" "$TMP_CON2"; }
trap cleanup EXIT HUP INT TERM

ok()   { printf '  [OK]   %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN] %s\n' "$*"; WARN=$((WARN+1)); }

[ -f "$CONFIG" ] || { echo "::error::依赖守卫需要 make defconfig 后的 .config: $CONFIG"; exit 1; }
[ -f "$PREC" ] || warn "来源优先级文件缺失: $PREC（仅做版本检查）"

# 归一化：大小写、alpha/beta/rc/pre 分隔符、~0 后缀、_ / - 分隔符、重复点
norm() {
	echo "$1" | tr '[:upper:]' '[:lower:]' \
		| sed -E 's/^v//; s/-?(alpha|beta|rc|pre)[._-]*/.\1./g; s/~[0-9]*//g; s/[_-]+/./g; s/\.\././g; s/\.\././g'
}
ver_ge() {
	a=$(norm "$1"); b=$(norm "$2")
	[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -1)" = "$a" ]
}
ver_eq() { [ "$(norm "$1")" = "$(norm "$2")" ]; }

# 优先读字面量版本字段：PKG_UPSTREAM_VERSION > PKG_VERSION > PKG_SOURCE_DATE；
# 跳过 $(...) 动态值（linkease 等包用 PKG_SOURCE_DATE 代替 PKG_VERSION）。
read_version() {
	mf="$1"
	for key in PKG_UPSTREAM_VERSION PKG_VERSION PKG_SOURCE_DATE; do
		v=$(sed -n "s/^${key}[?:]*=[[:space:]]*//p" "$mf" 2>/dev/null | head -1)
		v=${v%%#*}
		v=$(printf '%s' "$v" | sed 's/[[:space:]]*$//')
		case "$v" in
			''|*'$('*) continue ;;
		esac
		printf '%s\n' "$v"
		return 0
	done
	return 1
}

preferred_feed() {
	[ -f "$PREC" ] || return 0
	awk -v p="$1" '$1==p {print $2; exit}' "$PREC" 2>/dev/null
}

# 找包的有效 Makefile：优先优先级文件指定的 feed，再按 feeds/* -> package/* 顺序
find_makefile() {
	pkg="$1"
	feed=$(preferred_feed "$pkg" || true)
	if [ -n "$feed" ] && [ -f "$ROOT/package/feeds/$feed/$pkg/Makefile" ]; then
		readlink -f "$ROOT/package/feeds/$feed/$pkg/Makefile" 2>/dev/null \
			|| printf '%s\n' "$ROOT/package/feeds/$feed/$pkg/Makefile"
		return 0
	fi
	for mf in "$ROOT"/package/feeds/*/"$pkg"/Makefile \
	          "$ROOT"/package/"$pkg"/Makefile \
	          "$ROOT"/feeds/*/"$pkg"/Makefile; do
		if [ -f "$mf" ]; then
			readlink -f "$mf" 2>/dev/null || printf '%s\n' "$mf"
			return 0
		fi
	done
	return 1
}

selected() { grep -Fqx "CONFIG_PACKAGE_$1=y" "$CONFIG"; }

check_constraint() {
	consumer="$1"
	constraint="$2"
	name=$(printf '%s\n' "$constraint" | sed -E 's/^([A-Za-z0-9_.+-]+).*/\1/; s/^[+!]//')
	op=$(printf '%s\n' "$constraint" | sed -E 's/.*\([[:space:]]*(>=|<=|!=|>|<|=)[[:space:]]*.*/\1/')
	need=$(printf '%s\n' "$constraint" | sed -E 's/.*\([[:space:]]*(>=|<=|!=|>|<|=)[[:space:]]*([^)]*)\).*/\2/' | sed 's/[[:space:]]*$//')
	[ -n "$name" ] && [ -n "$op" ] && [ -n "$need" ] || return 0

	case "$need" in
		*'$('*) warn "$consumer -> $name 版本约束含动态片段 '$need'，跳过（需人工核对）"; return 0 ;;
	esac
	if ! selected "$name"; then
		warn "$consumer -> $name 未在 .config 中显式选中（defconfig 后仍未选中请人工核对）"
		return 0
	fi

	pmf=$(find_makefile "$name" || true)
	if [ -z "$pmf" ]; then bad "找不到 $name 的 Makefile（consumer=$consumer）"; return 0; fi
	have=$(read_version "$pmf" || true)
	if [ -z "$have" ]; then bad "$name 读不到版本（$pmf，consumer=$consumer）"; return 0; fi

	case "$op" in
		'>=') if ver_ge "$have" "$need"; then ok "$consumer -> $name $have 满足 >= $need"; else bad "$consumer -> $name $have 不满足 >= $need"; fi ;;
		'>')  if ver_ge "$have" "$need" && ! ver_eq "$have" "$need"; then ok "$consumer -> $name $have 满足 > $need"; else bad "$consumer -> $name $have 不满足 > $need"; fi ;;
		'<=') if ! ver_ge "$have" "$need" || ver_eq "$have" "$need"; then ok "$consumer -> $name $have 满足 <= $need"; else bad "$consumer -> $name $have 不满足 <= $need"; fi ;;
		'<')  if ! ver_ge "$have" "$need"; then ok "$consumer -> $name $have 满足 < $need"; else bad "$consumer -> $name $have 不满足 < $need"; fi ;;
		'=')  if ver_eq "$have" "$need"; then ok "$consumer -> $name $have 满足 = $need"; else bad "$consumer -> $name $have 不满足 = $need（实际 $have）"; fi ;;
		'!=') if ! ver_eq "$have" "$need"; then ok "$consumer -> $name $have 满足 != $need"; else bad "$consumer -> $name $have 不应等于 $need"; fi ;;
		*) warn "不支持的比较符 '$op'（$consumer -> $name），跳过" ;;
	esac
}

check_makefile() {
	mf="$1"
	consumer="$2"
	awk '
		/^([A-Za-z_][A-Za-z0-9_]*)?(DEPENDS|EXTRA_DEPENDS)[[:space:]]*[+?:]?=/ {
			line=$0; sub(/#.*/, "", line); print line
		}
	' "$mf" 2>/dev/null > "$TMP_CON" || true
	grep -oE '[A-Za-z0-9_.+-]+[[:space:]]*\([[:space:]]*(>=|<=|!=|>|<|=)[[:space:]]*[^)]+\)' "$TMP_CON" 2>/dev/null > "$TMP_CON2" || true
	while IFS= read -r c; do
		check_constraint "$consumer" "$c"
	done < "$TMP_CON2"
}

echo "== 通用依赖版本一致性守卫（编译前 fail-fast）=="

grep '^CONFIG_PACKAGE_.*=y$' "$CONFIG" > "$TMP_SEL" || true
checked=0
while IFS= read -r sym; do
	pkg=${sym#CONFIG_PACKAGE_}
	pkg=${pkg%=y}
	mf=$(find_makefile "$pkg" || true)
	[ -n "$mf" ] || continue
	check_makefile "$mf" "$pkg"
	checked=$((checked+1))
done < "$TMP_SEL"
echo "  已检查 $checked 个选中包的版本化依赖"

if [ -f "$PREC" ]; then
	echo "== 同名包来源优先级 =="
	while read -r pkg feed rest; do
		case "$pkg" in ''|\#*) continue ;; esac
		[ -n "$feed" ] || continue
		want="$ROOT/package/feeds/$feed/$pkg/Makefile"
		if [ ! -f "$want" ]; then
			bad "$pkg 未从 $feed feed 生效（期望 $want）"
			continue
		fi
		for d in "$ROOT"/package/feeds/*/"$pkg"; do
			[ -e "$d" ] || continue
			owner=$(basename "$(dirname "$d")")
			[ "$owner" = "$feed" ] && continue
			bad "$pkg 仍存在其他 feed 同名链接: $d（期望仅 $feed）"
		done
		ok "$pkg 生效来源 = $feed"
	done < "$PREC"
fi

if [ "$FAIL" -gt 0 ]; then
	echo "::error::依赖版本一致性守卫失败：$FAIL 项，拒绝进入耗时编译"
	exit 1
fi
echo "依赖版本一致性守卫通过 ✅（告警 $WARN 项）"
