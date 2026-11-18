#!/bin/sh
# 按 feed-precedence.txt 固定同名包的生效来源。
#
# 用法: sh scripts/feed-sources.sh <iStoreOS源码根目录> [feed-precedence.txt]
# 默认优先级文件: <源码根>/../configs/feed-precedence.txt
#
# 背景: feeds install -a 会按 feed 顺序安装同名包；官方 packages 的旧版
# sing-box 会占用 package/feeds/packages/sing-box，导致 small 的新版无法生效。
# feeds install -f 只覆盖 core 包，必须先删其他 feed 的同名链接再按名安装。
set -eu

ROOT="${1:?用法: feed-sources.sh <iStoreOS源码根目录> [precedence-file]}"
PREC="${2:-$ROOT/../configs/feed-precedence.txt}"
[ -f "$PREC" ] || { echo "::error::来源优先级文件缺失: $PREC"; exit 1; }

echo "== 同名包来源优先级处理 =="
while read -r pkg feed rest; do
	case "$pkg" in ''|\#*) continue ;; esac
	[ -n "$feed" ] || continue
	echo "  $pkg -> feed $feed"

	# 1) 删除其他 feed 的同名链接（只删链接，不删 feeds/ 源目录）
	for d in "$ROOT"/package/feeds/*/"$pkg"; do
		[ -e "$d" ] || continue
		owner=$(basename "$(dirname "$d")")
		[ "$owner" = "$feed" ] && continue
		echo "    移除 $owner 同名链接: $d"
		if [ -L "$d" ]; then
			rm -f "$d"
		elif [ -d "$d" ]; then
			rmdir "$d" 2>/dev/null || {
				echo "::error::$d 是真实目录而非 feeds 符号链接，拒绝递归删除，请人工核对"
				exit 1
			}
		else
			rm -f "$d"
		fi
	done

	# 2) 目标 feed 缺链接时按名安装
	if [ ! -f "$ROOT/package/feeds/$feed/$pkg/Makefile" ]; then
		echo "    从 $feed 安装 $pkg"
		( cd "$ROOT" && ./scripts/feeds install -p "$feed" "$pkg" >/dev/null )
	fi

	# 3) 验证生效路径
	link=$(readlink -f "$ROOT/package/feeds/$feed/$pkg" 2>/dev/null || true)
	case "$link" in
		*"/feeds/$feed/"*) echo "    生效源: $link" ;;
		*) echo "::error::$pkg 未从 $feed feed 生效（link=${link:-<无>}）"; exit 1 ;;
	esac
done < "$PREC"
echo "同名包来源优先级处理完成 ✅"
