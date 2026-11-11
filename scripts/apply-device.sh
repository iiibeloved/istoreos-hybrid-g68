#!/bin/sh
# =============================================================================
#  把 G68 (NSY G68-PLUS / RK3568) 设备层应用到 iStoreOS 源码树
#
#  方案：u-boot 改动以 OpenWrt patches 形式投递（patch 101 等价）。
#
#  ★ 关键集成点（此前的实现是死路径，已修正）★
#  iStoreOS 的 uboot-rockchip 从官方 tarball 构建：
#    include/u-boot.mk:
#      PKG_SOURCE = u-boot-2024.10.tar.bz2
#      PKG_BUILD_DIR = build_dir/.../u-boot-2024.10
#  构建系统只读取「解压后的 build_dir」，绝不读取
#  package/boot/uboot-rockchip/src/。因此把改动 cp 到 src/ 是无效操作——
#  补丁永远不会进二进制，长按 Reset 进 MaskROM 也就不会生效。
#  正确做法：把改动作为 patches 放进 patches-<版本>/，由 OpenWrt 在解压
#  tarball 后自动打补丁（与 immortalwrt 的 patch 101 同一机制）。
#
#  补丁清单（device/uboot/patches/，对应 immortalwrt patch 101）：
#   100  arch/arm/mach-rockchip/boot_mode.c      SPL 读 SARADC 通道0 → 写 BROM 下载标志（核心）
#   101  arch/arm/mach-rockchip/rk3568/rk3568.c  spl_board_init → setup_boot_mode 调用链
#   102  arch/arm/mach-rockchip/Makefile         把 boot_mode.o 编入 SPL
#   103  arch/arm/dts/Makefile                   登记 rk3568-nsy-g68-plus.dtb
#   104  configs/nsy-g68-plus-rk3568_defconfig   （新增板级 defconfig）
#   105  arch/arm/dts/rk3568-nsy-g68-plus.dts    （新增板级 dts）
#   106  arch/arm/dts/rk3568-nsy-g68-plus-u-boot.dtsi（新增板级 dtsi）
#
#  版本守卫：OVERLAY_BASE 锁定 u-boot 基准版本（2024.10），iStoreOS 升级
#  u-boot 时版本守卫直接判构建失败并提示重新生成 patches，绝不带病构建。
# =============================================================================
set -eu

ROOT="${1:?用法: apply-device.sh <iStoreOS源码根目录>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEV="$HERE/device"
UB="$ROOT/package/boot/uboot-rockchip"
LOG="$HERE/apply-device.log"
: > "$LOG"

say() { echo "[apply-device] $*" | tee -a "$LOG"; }
die() { echo "[apply-device][FATAL] $*" | tee -a "$LOG" >&2; exit 1; }

[ -d "$UB" ] || die "找不到 $UB（iStoreOS 源码根目录不对？）"
[ -d "$DEV/uboot/patches" ] || die "缺少 device/uboot/patches（u-boot 补丁目录）"

# ---------- 0) 版本守卫 ----------
UV=$(sed -n 's/^PKG_VERSION:=//p' "$UB/Makefile" | head -1)
[ -n "$UV" ] || die "无法从 $UB/Makefile 读出 PKG_VERSION"
BASE=$(cat "$DEV/uboot/OVERLAY_BASE" 2>/dev/null || echo "")
[ "$UV" = "$BASE" ] || die "u-boot 版本不匹配：iStoreOS=$UV，patches 基准=${BASE:-未定义}。
  iStoreOS 升级了 u-boot，请按新版本重新生成 device/uboot/patches（patch 101 等价）。"
say "u-boot 版本校验通过：$UV"

# ---------- 1) u-boot 补丁：拷贝到 patches-<版本>/（构建时由 OpenWrt 应用）----------
mkdir -p "$UB/patches-$UV"
cp -f "$DEV/uboot/patches/"*.patch "$UB/patches-$UV/"
say "u-boot 补丁已放入 $UB/patches-$UV/（build 时由 OpenWrt 应用到 build_dir/u-boot-$UV）"

# ---------- 2) 内核补丁（XPCS / SGMII 2.5G / combphy sgmii-mac-sel）----------
if [ -d "$DEV/kernel-patches" ]; then
	mkdir -p "$ROOT/target/linux/rockchip/patches-6.6"
	for pf in "$DEV/kernel-patches"/*.patch; do
		[ -f "$pf" ] || continue
		base=$(basename "$pf")
		cp -f "$pf" "$ROOT/target/linux/rockchip/patches-6.6/$base"
	done
	say "内核补丁已放置: $(ls "$DEV/kernel-patches" | tr '\n' ' ')"
fi

# ---------- 3) 内核 DTS（板级，内核构建使用）----------
mkdir -p "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus.dts" \
      "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/"
say "内核 DTS 已放置（target/linux/rockchip/files/.../rk3568-nsy-g68-plus.dts）"

# ---------- 4) uboot-rockchip/Makefile：插入目标定义 + TARGETS ----------
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
	awk '
		/^UBOOT_TARGETS/ { inlist=1 }
		inlist && /-rk3568[ \t]*\\?$/ && !done {
			print; print "  nsy-g68-plus-rk3568 \\"; done=1; next
		}
		{ print }
	' "$MK" > "$MK.new2" && mv "$MK.new2" "$MK"
	sed -n '/^UBOOT_TARGETS/,/^$/p' "$MK" | grep -q "nsy-g68-plus-rk3568" \
		|| die "UBOOT_TARGETS 插入失败（iStoreOS Makefile 结构变化）"
	say "uboot-rockchip/Makefile: UBOOT_TARGETS 已加入 nsy-g68-plus-rk3568"
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

# ---------- 6) scripts/gen_image_generic.sh：rootfs_data 默认 4096 MiB ----------
GEN="$ROOT/scripts/gen_image_generic.sh"
[ -f "$GEN" ] || die "找不到 $GEN"
if ! grep -q 'ROOTFS_DATA_PARTSIZE' "$GEN"; then
	sed -i 's/^USERDATASIZE="2048"$/USERDATASIZE="${ROOTFS_DATA_PARTSIZE:-4096}"/' "$GEN"
	grep -q 'ROOTFS_DATA_PARTSIZE' "$GEN" \
		|| die "gen_image_generic.sh 结构变化：未找到 USERDATASIZE=\"2048\"，请检查 iStoreOS 是否改了分区脚本"
	say "gen_image_generic.sh: rootfs_data 默认 4096 MiB（ROOTFS_DATA_PARTSIZE 可覆盖）"
else
	say "gen_image_generic.sh: 已是可覆盖形式，跳过"
fi

say "完成（u-boot $UV，patches 投递 + 板级文件 + 构建系统插入 + rootfs_data=4096）"
