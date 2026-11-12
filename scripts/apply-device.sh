#!/bin/sh
# =============================================================================
#  把 G68 (NSY G68-PLUS / RK3568) 设备层应用到 iStoreOS 源码树
#
#  投递方式：**overlay-only**（不使用任何 u-boot .patch）
#    OpenWrt 的 Build/Prepare/Default 在解压 tarball 后执行：
#        [ ! -d ./src/ ] || cp ./src/. $PKG_BUILD_DIR
#    因此把改动文件放进 package/boot/uboot-rockchip/src/ 即会在编译前进入源码树。
#    我们投递 4 个"上游原版 + patch101 等价改动"的完整文件：
#      arch/arm/mach-rockchip/Makefile          boot_mode.o 编入 SPL
#      arch/arm/mach-rockchip/boot_mode.c       SPL 读 SARADC ch0 → 写 BROM 标志→复位进 MaskROM
#      arch/arm/mach-rockchip/rk3568/rk3568.c   spl_board_init() → setup_boot_mode()
#      arch/arm/dts/Makefile                    登记 rk3568-nsy-g68-plus.dtb
#    其余为纯新增板级文件（dts/dtsi/defconfig）与内核 DTS。
#
#  版本守卫：device/uboot/OVERLAY_BASE 锁定 u-boot 基准版本；iStoreOS 升级
#  u-boot 时直接失败并提示重新生成 overlay，绝不带病构建。
#
#  结束时调用 scripts/verify-maskrom.sh 校验核心功能（长按 Reset→MaskROM），
#  不通过则构建失败。
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
  iStoreOS 升级 u-boot 后请重新生成 device/uboot/overlay（u-boot v$UV 原版 + patch101 等价改动）。"
say "u-boot 版本校验通过：$UV"

# ---------- 1) overlay：4 个上游文件的完整替换 ----------
cp -a "$DEV/uboot/overlay/." "$UB/src/"
say "overlay 已投递到 $UB/src/（Makefile / boot_mode.c / rk3568.c / dts/Makefile）"

# ---------- 2) 纯新增板级文件 ----------
mkdir -p "$UB/src/arch/arm/dts" "$UB/src/configs"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus.dts"         "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/rk3568-nsy-g68-plus-u-boot.dtsi" "$UB/src/arch/arm/dts/"
cp -f "$DEV/uboot/static/nsy-g68-plus-rk3568_defconfig"   "$UB/src/configs/"
say "板级文件已放置（u-boot dts / dtsi / defconfig）"

# ---------- 3) 内核补丁（XPCS / SGMII 2.5G / combphy / dwmac 自适应）----------
if [ -d "$DEV/kernel-patches" ]; then
	mkdir -p "$ROOT/target/linux/rockchip/patches-6.6"
	cp -f "$DEV/kernel-patches/"*.patch "$ROOT/target/linux/rockchip/patches-6.6/"
	say "内核补丁已放置: $(ls "$DEV/kernel-patches" | tr '\n' ' ')"
fi

# ---------- 4) 内核 DTS ----------
mkdir -p "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip"
cp -f "$DEV/kernel-dts/rk3568-nsy-g68-plus.dts" \
      "$ROOT/target/linux/rockchip/files/arch/arm64/boot/dts/rockchip/"
say "内核 DTS 已放置"

# ---------- 5) uboot-rockchip/Makefile：插入目标定义 + TARGETS ----------
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

# ---------- 6) image/armv8.mk：追加 Device 块 ----------
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

# ---------- 7) gen_image_generic.sh：rootfs_data 默认 4096 MiB ----------
GEN="$ROOT/scripts/gen_image_generic.sh"
[ -f "$GEN" ] || die "找不到 $GEN"
if ! grep -q 'ROOTFS_DATA_PARTSIZE' "$GEN"; then
	sed -i 's/^USERDATASIZE="2048"$/USERDATASIZE="${ROOTFS_DATA_PARTSIZE:-4096}"/' "$GEN"
	grep -q 'ROOTFS_DATA_PARTSIZE' "$GEN" \
		|| die "gen_image_generic.sh 结构变化：未找到 USERDATASIZE=\"2048\""
	say "gen_image_generic.sh: rootfs_data 默认 4096 MiB"
fi

# ---------- 7.5) 自定义 files/（Argon 必应壁纸等）----------
if [ -d "$DEV/files" ]; then
	mkdir -p "$ROOT/files"
	cp -a "$DEV/files/." "$ROOT/files/"
	say "自定义文件已放置到 $ROOT/files/（$(cd "$DEV/files" && find . -type f | wc -l) 个文件）"
fi

# ---------- 7.55) 中文覆盖数据（按已安装应用条件投递）----------
if [ -d "$DEV/i18n-overlay" ]; then
	mkdir -p "$ROOT/files/usr/share/g68/i18n-overlay"
	cp -a "$DEV/i18n-overlay/." "$ROOT/files/usr/share/g68/i18n-overlay/"
	say "中文覆盖数据已放置: files/usr/share/g68/i18n-overlay/（$(cd "$DEV/i18n-overlay" && find . -type f | wc -l) 个文件）"
fi

# ---------- 7.6) 设备内核配置对齐（移植 immortalwrt 已验证配置）----------
if [ -f "$DEV/kernel-config" ]; then
	KCONF="$ROOT/target/linux/rockchip/armv8/config-6.6"
	[ -f "$KCONF" ] || { say "警告: 找不到 $KCONF，跳过内核配置对齐"; }
	if [ -f "$KCONF" ]; then
		if grep -q "G68 设备内核配置" "$KCONF"; then
			say "内核配置已对齐（跳过）"
		else
			{ echo ""; echo "# --- G68 设备内核配置（来自 immortalwrt 基线）---"; cat "$DEV/kernel-config"; } >> "$KCONF"
			say "已向 config-6.6 追加 G68 内核配置（RTL8367S DSA 等）"
		fi
	fi
fi

# ---------- 8) 核心功能守卫 ----------
sh "$HERE/scripts/verify-maskrom.sh" "$ROOT" || die "长按 Reset→MaskROM 核心功能校验失败"
say "完成（overlay-only，u-boot $UV，核心功能守卫通过）"
