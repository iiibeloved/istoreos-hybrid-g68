#!/bin/sh
# =============================================================================
#  把 G68 (NSY G68-PLUS / RK3568) 设备层应用到 iStoreOS 源码树
#
#  设计原则（"要素化"，不用 .patch 文件）：
#   - 纯新增文件：DTS / u-boot DTS+DTSI / defconfig  -> 直接放入对应 src/ 覆盖目录
#   - 需要改动的上游文件（u-boot rk3568.c、arch/arm/dts/Makefile、
#     uboot-rockchip/Makefile、image/armv8.mk）：构建前"现取上游原文 + 自动注入/追加"，
#     带锚点检查与幂等标记；上游结构变化时明确报错，不静默出错。
#
#  用法：
#    apply-device.sh <iStoreOS源码根目录>
#  环境：
#    UBOOT_GIT_MIRROR  取上游 u-boot 单文件用的 raw 前缀（默认 gh 代理 + u-boot 官方）
# =============================================================================
set -eu

ROOT="${1:?用法: apply-device.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
UB="$ROOT/package/boot/uboot-rockchip"
RAW="${UBOOT_GIT_MIRROR:-https://raw.githubusercontent.com/u-boot/u-boot}"
LOG="$HERE/apply-device.log"
: > "$LOG"

say() { echo "[apply-device] $*" | tee -a "$LOG"; }
die() { echo "[apply-device][FATAL] $*" | tee -a "$LOG" >&2; exit 1; }

[ -d "$UB" ] || die "找不到 $UB（iStoreOS 源码根目录不对？）"

# ---------- 0) 读取 iStoreOS 的 u-boot 版本与来源 ----------
UV=$(sed -n 's/^PKG_VERSION:=//p' "$UB/Makefile" | head -1)
[ -n "$UV" ] || die "无法从 $UB/Makefile 读出 PKG_VERSION"
SRC_PROTO=$(sed -n 's/^PKG_SOURCE_PROTO:=//p' "$UB/Makefile" | head -1)
SRC_URL=$(sed -n 's/^PKG_SOURCE_URL:=//p' "$UB/Makefile" | head -1)
SRC_VER=$(sed -n 's/^PKG_SOURCE_VERSION:=//p' "$UB/Makefile" | head -1)
say "iStoreOS u-boot: version=$UV proto=${SRC_PROTO:-tarball} url=${SRC_URL:-denx} commit=${SRC_VER:-n/a}"

TAG="v$UV"
[ -n "$SRC_VER" ] && TAG=""
say "u-boot 上游基准: ${SRC_URL:-https://source.denx.de/u-boot/u-boot} @ ${TAG:-$SRC_VER}"

# ---------- 1) 纯新增文件 ----------
mkdir -p "$UB/src/arch/arm/dts" "$UB/src/configs" \
         "$UB/src/arch/arm/mach-rockchip/rk3568" \
         "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"

cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus.dts"        "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus-u-boot.dtsi" "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig"   "$UB/src/configs/"
cp -f "$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" \
      "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/"
say "静态设备文件已放置（u-boot dts/dtsi/defconfig + 内核 dts）"

# ---------- 2) 生成 u-boot rk3568.c（上游原文 + 注入块） ----------
fetch_uboot_file() {  # $1=相对路径  $2=输出文件
	url="${RAW}/${TAG}/$1"
	[ -n "$TAG" ] || url="${RAW}/${SRC_VER}/$1"
	if ! curl -fsSL --max-time 120 "$url" -o "$2"; then
		die "取上游 u-boot 文件失败: $url"
	fi
	[ -s "$2" ] || die "上游文件为空: $url"
}

GEN="$HERE/.gen"; mkdir -p "$GEN"
fetch_uboot_file "arch/arm/mach-rockchip/rk3568/rk3568.c" "$GEN/rk3568.c.upstream"
grep -q "arch_cpu_init" "$GEN/rk3568.c.upstream" || die "上游 rk3568.c 锚点 arch_cpu_init 缺失（u-boot 结构大改）"

if grep -q "spl_board_init" "$GEN/rk3568.c.upstream"; then
	say "上游已含 spl_board_init()：仅注入通道覆盖（rockchip_dnl_key_pressed）"
	BLOCK="$DEV/uboot/inject/rk3568-key-block.c"
else
	say "上游无 spl_board_init()：注入完整块（SPL 按键 + 通道覆盖）"
	BLOCK="$DEV/uboot/inject/rk3568-key-block.c"
fi

cp -f "$GEN/rk3568.c.upstream" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c"
cat "$BLOCK" >> "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c"
# 幂等：文件中注入标记必须恰好一组
MARK=$(grep -c "NSY-G68 long-press Reset -> MaskROM: begin" "$UB/src/arch/arm/mach-rockchip/rk3568/rk3568.c" || true)
[ "$MARK" = "1" ] || die "注入块数量异常: $MARK"
say "rk3568.c 生成完成（上游 $(wc -l < "$GEN/rk3568.c.upstream") 行 + 注入块）"

# ---------- 3) u-boot arch/arm/dts/Makefile：追加 dtb 行 ----------
fetch_uboot_file "arch/arm/dts/Makefile" "$GEN/dts.Makefile.upstream"
grep -q "dtb-\$(CONFIG_ROCKCHIP_RK" "$GEN/dts.Makefile.upstream" || die "上游 arch/arm/dts/Makefile 不存在 rockchip dtb 列表（结构变化）"
cp -f "$GEN/dts.Makefile.upstream" "$UB/src/arch/arm/dts/Makefile"
printf '\n# NSY-G68 (added by istoreos-hybrid-g68)\ndtb-$(CONFIG_ROCKCHIP_RK3568) += rk3568-nsy-g68-plus.dtb\n' \
	>> "$UB/src/arch/arm/dts/Makefile"
say "u-boot dts Makefile 已追加密钥 dtb 条目"

# ---------- 4) uboot-rockchip/Makefile：插入 U-Boot/nsy-g68-plus 定义 + TARGETS ----------
MK="$UB/Makefile"
if ! grep -q "U-Boot/nsy-g68-plus-rk3568" "$MK"; then
	awk '
		/^define U-Boot\/rk3568\/Default/ && !done {
			print "define U-Boot/nsy-g68-plus-rk3568"
			print "  $(U-Boot/rk3568/Default)"
			print "  NAME:=NSY G68 PLUS"
			print "  BUILD_DEVICES:= \\"
			print "    nsy_g68-plus"
			print "endef"
			print ""
			done=1
		}
		{ print }
	' "$MK" > "$MK.new" && mv "$MK.new" "$MK"
	say "uboot-rockchip/Makefile: 已插入 U-Boot/nsy-g68-plus-rk3568"
fi

if ! sed -n '/^UBOOT_TARGETS/,/^$/p' "$MK" | grep -q "nsy-g68-plus-rk3568"; then
	# 追加到 rk3568 目标列表（兼容不同写法：找首次出现的 rk3568 目标行后追加）
	awk '
		/^UBOOT_TARGETS/ { inlist=1 }
		inlist && /-rk3568[ \t]*\\?$/ && !done {
			print; print "  nsy-g68-plus-rk3568 \\"; done=1; next
		}
		{ print }
	' "$MK" > "$MK.new2" && mv "$MK.new2" "$MK"
	# 若没有匹配到，退化为在文件末尾（BuildPackage 之前）追加一行
	if ! grep -q "nsy-g68-plus-rk3568 \\\\" "$MK"; then
		die "UBOOT_TARGETS 中未能插入 nsy-g68-plus-rk3568，请检查 iStoreOS 的 Makefile 结构"
	fi
fi

# ---------- 5) image/armv8.mk：追加 Device 块 ----------
IMG="$ROOT/target/linux/rockchip/image/armv8.mk"
[ -f "$IMG" ] || die "找不到 $IMG"
if ! grep -q "Device/nsy_g68-plus" "$IMG"; then
	cat >> "$IMG" <<'IMGBLOCK'

# ---- NSY G68-PLUS (RK3568) ----
define Device/nsy_g68-plus
  DEVICE_VENDOR := NSY
  DEVICE_MODEL := G68-PLUS
  SOC := rk3568
  DEVICE_DTS := rockchip/rk3568-nsy-g68-plus
  UBOOT_DEVICE_NAME := nsy-g68-plus-rk3568
endef
TARGET_DEVICES += nsy_g68-plus
IMGBLOCK
	say "image/armv8.mk: 已追加 Device/nsy_g68-plus"
fi

say "完成。u-boot 版本=$UV"
