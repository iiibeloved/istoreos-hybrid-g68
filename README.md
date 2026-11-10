# NSY G68-PLUS · iStoreOS 24.10 杂交固件（RK3568）

> 把现有 immortalwrt 的设备层（DTS / u-boot 长按 Reset 进 MaskROM / 分区）搬到 **iStoreOS 24.10** 基座上。
> 刷机方式与 immortalwrt **完全一致**：USB 双公头 + RKDevTool + 长按 Reset 进 MaskROM + **强制按地址写**。

## 特性

- **长按 Reset 进 MaskROM**（不用短接触点）：SPL 阶段读 SARADC 通道 0，按下即写 BROM 下载标志并复位
- 设备树 / u-boot 板级文件来自 NSY G68 实机验证过的配置
- 基座为 iStoreOS **官方源**（`istoreos-24.10`），固件为**通用版**（不含任何自定义 uci-defaults / 开机脚本）
- 上游 iStoreOS 有更新自动触发构建；否则每周日 02:00 CST 检查一次
- 构建前自动自检（overlay、defconfig、DTS、镜像定义 + u-boot 版本守卫），u-boot 单独编译并做源码/strings 断言，通过后才全量构建

## 快速开始

```sh
# 本仓库只做设备层；构建在 GitHub Actions 中完成
# 手动触发：
gh workflow run build.yml -f stage=full -f publish=true
```

产物：`bin/targets/rockchip/armv8/*nsy_g68-plus*sysupgrade.img.gz`（Release 附带 sha256）

## 目录

```
device/            设备层（内核 DTS / u-boot defconfig+dts / 按键链路 overlay）
scripts/
  apply-device.sh  把设备层应用到 iStoreOS 源码（overlay 整文件覆盖，幂等）
  selftest.sh      构建前静态自检
configs/           固件 defconfig
docs/design.md     原理、差异、刷机、风险
```

## 刷机

1. USB 双公头线连接电脑与设备（OTG 口）
2. RKDevTool v3.18 + 驱动 v5.12
3. 断电 → **按住 Reset** → 上电 → 松开 → 出现 MaskROM 设备
4. 高级功能 → Boot：`rk356x_spl_loader_v1.21.113.bin` → 下载
5. 获取当前存储 → **擦除所有**
6. 下载镜像（解压后的 `.img`）→ **勾选「强制按地址写」** → 执行

## 文档

- [设计文档](docs/design.md)：原理、与 immortalwrt 的差异、分区、风险

## 许可

设备树与板级配置源自 ImmortalWrt/OpenWrt（GPL-2.0）；仓库脚本 MIT。
