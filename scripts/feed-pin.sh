#!/bin/sh
# 按 feeds.lock 固定滚动 feed 的提交，防 upstream main 静默漂移。
#
# 用法: sh scripts/feed-pin.sh <iStoreOS源码根目录> [feeds.lock]
# 默认锁文件: <源码根>/../configs/feeds.lock
set -eu

ROOT="${1:?用法: feed-pin.sh <iStoreOS源码根目录> [feeds.lock]}"
LOCK="${2:-$ROOT/../configs/feeds.lock}"
[ -f "$LOCK" ] || { echo "::error::feed 锁文件缺失: $LOCK"; exit 1; }

echo "== 固定 feed 提交（防 main 漂移）=="
while read -r feed sha rest; do
	case "$feed" in ''|\#*) continue ;; esac
	[ -n "$sha" ] || continue
	d="$ROOT/feeds/$feed"
	if [ ! -d "$d/.git" ]; then
		echo "::warning::feed $feed 不是 git 仓库，跳过 pin"
		continue
	fi
	cur=$(git -C "$d" rev-parse HEAD 2>/dev/null || true)
	if [ "$cur" = "$sha" ]; then
		echo "  $feed 已锁定 $sha"
		continue
	fi
	# iStoreOS 的 src-git 用 git clone --depth 1 浅克隆，锁定提交通常不在
	# 浅历史里，直接 checkout 会失败。先按需抓取该单个提交（等价 OpenWrt
	# 官方 init_commit 的 git fetch --depth=1 origin <sha> 做法）。
	if ! git -C "$d" cat-file -e "$sha^{commit}" 2>/dev/null; then
		echo "  浅克隆缺少 $sha，按需抓取..."
		git -C "$d" fetch --depth=1 origin "$sha" >/dev/null 2>&1 || {
			echo "::error::feed $feed 无法抓取锁定提交 $sha（上游可能已强制推送，需更新 configs/feeds.lock）"
			exit 1
		}
	fi
	git -C "$d" -c advice.detachedHead=false checkout -q "$sha" || {
		echo "::error::feed $feed 无法切到锁定提交 $sha（上游可能已强制推送，需更新 configs/feeds.lock）"
		exit 1
	}
	echo "  $feed $cur -> $(git -C "$d" rev-parse --short HEAD)"
done < "$LOCK"
echo "feed 提交固定完成 ✅"
