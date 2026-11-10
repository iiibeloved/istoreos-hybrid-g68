#!/bin/sh
# =============================================================================
#  把 G68 (NSY G68-PLUS / RK3568) 设备层应用到 iStoreOS 源码树
#
#  方案（不用 .patch，全部是文件覆盖/追加，保持干净）：
#   - 纯新增文件：板级 DTS / DTSI / defconfig          -> uboot-rockchip/src/
#   - 上游改动的文件（3 个）以"已验证的完整文件"覆盖：
#       arch/arm/mach-rockchip/{Makefile,boot_mode.c}
#       arch/arm/mach-rockchip/rk3568/rk3568.c
#     这些文件 = u-boot 2024.10 上游 + immortalwrt 实机验证过的 patch 101 等价改动
#       （boot_mode.o 编入 SPL、RK_DNL_ADC_CHAN=0、spl_board_init() 调 setup_boot_mode()）
#   - arch/arm/dts/Makefile 同样覆盖（登记我们的 dtb）
#   - 构建系统两处插入（幂等、带标记）：U-Boot 目标定义、镜像 Device 块
#
#  版本守卫：overlay 基准是 u-boot 2024.10；iStoreOS 升级 u-boot 时必须重新生成
#            overlay，否则直接失败并提示，绝不带病构建。
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
[ -d "$DEV/uboot/overlay" ] || die "缺少 device/uboot/overlay"

# ---------- 0) 版本守卫 ----------
UV=$(sed -n 's/^PKG_VERSION:=//p' "$UB/Makefile" | head -1)
[ -n "$UV" ] || die "无法从 $UB/Makefile 读出 PKG_VERSION"
BASE=$(cat "$DEV/uboot/OVERLAY_BASE" 2>/dev/null || echo "")
[ "$UV" = "$BASE" ] || die "u-boot 版本不匹配：iStoreOS=$UV，overlay 基准=${BASE:-未定义}。
  iStoreOS 升级了 u-boot，请按新版本重新生成 device/uboot/overlay：
    - arch/arm/mach-rockchip/{Makefile,boot_mode.c}
    - arch/arm/mach-rockchip/rk3568/rk3568.c
    - arch/arm/dts/Makefile
  生成方式：取 u-boot v$UV 原版，套用 immortalwrt 的
  patches/101-rockchip-boot_mode-Allow-rockchip_dnl_key_pressed-in-SPL.patch 后保存。"
say "u-boot 版本校验通过：$UV"

# ---------- 1) 覆盖层（含上游改动的 4 个文件）----------
cp -a "$DEV/uboot/overlay/." "$UB/src/"
say "overlay 已覆盖到 $UB/src/（Makefile / boot_mode.c / rk3568.c / dts/Makefile）"

# ---------- 2) 纯新增板级文件 ----------
mkdir -p "$UB/src/arch/arm/dts" "$UB/src/configs" \
         "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus.dts"         "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus-u-boot.dtsi" "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig"   "$UB/src/configs/"
cp -f "$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" \
      "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/"
say "板级文件已放置（u-boot dts/dtsi/defconfig + 内核 dts）"

# ---------- 3) uboot-rockchip/Makefile：插入目标定义 + TARGETS ----------
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

# ---------- 4) image/armv8.mk：追加 Device 块 ----------
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

say "完成（u-boot $UV，overlay 覆盖 + 板级文件 + 构建系统插入）"
