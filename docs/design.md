# G68 iStoreOS 杂交固件 · 设计文档

> 设备：NSY G68-PLUS（RK3568）　基座：iStoreOS 24.10（内核 6.6 / u-boot 2024.10）
> 目标：把现有 immortalwrt 的设备层（DTS / u-boot 按键 / 分区）搬到 iStoreOS 上，
> 实现 **长按 Reset 进 MaskROM**、与 immortalwrt 完全一致的刷机方式，且固件为**通用版**。

## 1. 长按 Reset 进 MaskROM 的原理（已实机验证于 immortalwrt）

```
上电 → BROM（读 boot-mode 寄存器 0xfdc20200，非 0xEF08A53C 则正常启动）
     → idbloader = TPL(DDR) + SPL
     → SPL 中读 SARADC 通道 0
          ├─ 按键按下（原始值 0..30）→ 写 0xEF08A53C 到 0xfdc20200 → do_reset()
          │                              → BROM 重新上电 → MaskROM（RKDevTool 可见）
          └─ 未按 → 正常启动 u-boot → kernel
```

关键三要素：

| 要素 | 来源 | 说明 |
| --- | --- | --- |
| `ROCKCHIP_BOOT_MODE_REG` 默认 `0xfdc20200` | u-boot `arch/arm/mach-rockchip/rk3568/Kconfig` | 上游自带，无需配置 |
| ADC 驱动默认开启 | u-boot `arch/arm/Kconfig`：`imply ADC` + `imply SARADC_ROCKCHIP` | 上游自带 |
| **SPL 阶段读 ADC 通道 0 并触发复位** | 上游需 patch 101 才能让 weak 按键检测在 SPL 生效 | 本仓库 `device/uboot/overlay/` 整文件覆盖（patch 101 等价） |

immortalwrt 侧原实现是 patch 101（修改 `boot_mode.c` / `Makefile` / `rk3568.c`）。
本仓库改为 **overlay 整文件覆盖**：`device/uboot/overlay/` 保存「u-boot 2024.10 上游
+ patch 101 等价改动」的完整文件，构建前 `cp -a` 覆盖进 u-boot 源码树。不产生 `.patch`
文件；`OVERLAY_BASE` 锁定基准版本（2024.10），iStoreOS 升级 u-boot 时版本守卫直接
判构建失败并提示重新生成 overlay，绝不带病构建。

## 2. 与 immortalwrt 的差异

| 项 | immortalwrt（现有） | iStoreOS 杂交（本仓库） |
| --- | --- | --- |
| 基座 | ImmortalWrt 24.10（fork） | iStoreOS `istoreos-24.10` |
| 内核 | 6.6 | 6.6 |
| u-boot | 2024.10 + patch 101 | 2024.10 + overlay（patch 101 等价改动，无 patch 文件） |
| 镜像流程 | `pine64-img`（32 MiB 预留，rootfs_data 4096） | `pine64-img`（**16 MiB 预留**，rootfs_data 2048，`RESET000` 标记自动重置） |
| 分区 | kernel 16M / rootfs 200M / rootfs_data 4096M | kernel 16M / rootfs 200M / **rootfs_data 2048M** |
| 刷机 | 双公头 + RKDevTool + 长按 Reset + **强制按地址写** | **完全一致** |
| 通用版 | 无自定义 uci-defaults | 无自定义 uci-defaults（本仓库不含任何 init/配置脚本） |

## 3. 设备层文件（`device/`）

```
device/
├── kernel-dts/rk3568-nsy-g68-plus.dts          # 内核 DTS（含 adc-keys recovery-key）
└── uboot/
    ├── static/
    │   ├── nsy-g68-plus-rk3568_defconfig        # 板级 u-boot defconfig
    │   ├── rk3568-nsy-g68-plus.dts              # u-boot 板级 DTS（&saradc okay / usb）
    │   └── rk3568-nsy-g68-plus-u-boot.dtsi      # u-boot dtsi（emmc 时序）
    ├── overlay/                                # u-boot 2024.10 上游 + patch 101 等价改动（整文件覆盖）
    │   └── arch/arm/mach-rockchip/
    │       ├── boot_mode.c                     # SPL 读 SARADC 通道 0 → 写 BROM 下载标志（核心）
    │       ├── rk3568/rk3568.c                 # spl_board_init → setup_boot_mode 调用链
    │       └── Makefile、dts/Makefile           # 把板级 dtb / boot_mode.o 纳入构建
    └── OVERLAY_BASE                            # overlay 基准版本（2024.10），版本守卫
```

## 4. 构建流程

```
check-upstream（定时/手动）→ 比对 upstream.lock 与 iStoreOS 分支 HEAD
prepare → clone iStoreOS → apply-device.sh（overlay 覆盖）→ selftest.sh（静态断言）
uboot-check → 只编 u-boot → 源码断言（boot_mode.c 含 rockchip_dnl_key_pressed / set_back_to_bootrom_dnl_flag）
             + strings 断言（download key pressed / adc_channel_single_shot / saradc）
             + .config 断言（ROCKCHIP_BOOT_MODE_REG=0xfdc20200）
build → 全量 make → 收集 img.gz + sha256 → Release（含刷机步骤）→ 回写 upstream.lock
失败 → 自动开 issue
```

触发条件：

| 事件 | 行为 |
| --- | --- |
| push（device/configs/scripts/workflow） | 全量构建 |
| 每周日 02:00 CST（cron `0 18 * * 6`） | 先比对上游 commit，有变化才构建 |
| workflow_dispatch | `stage=uboot` 只验证 u-boot；`stage=full` 全量 |

## 5. 刷机（与 immortalwrt 一致）

1. USB 双公头线连接电脑与设备（OTG，靠网口那个 USB）
2. RKDevTool v3.18 + 驱动 v5.12
3. 断电 → **按住 Reset** → 上电 → 松开 → 工具显示 MaskROM 设备
4. 高级功能 → Boot：`rk356x_spl_loader_v1.21.113.bin` → 下载
5. 获取当前存储 → **擦除所有**
6. 下载镜像（解压后的 `.img`）→ **勾选「强制按地址写」** → 执行

> 若长按无效，可用短接触点法兜底（BROM MaskROM，loader 与地址相同）。

## 6. 风险与回滚

| 风险 | 应对 |
| --- | --- |
| iStoreOS 升级 u-boot（2024.10 → 更新） | OVERLAY_BASE 版本守卫：版本不一致即构建失败，提示按新版本重新生成 overlay |
| 上游合并同类按键逻辑 | overlay 为整文件覆盖，会掩盖上游同类改动；版本守卫在 u-boot 升级时强制人工核对并重新生成 overlay |
| 内核 DTS 与 iStoreOS 6.6 不兼容 | 首次构建验证启动；必要时按 6.6 调整 DTS 属性 |
| 应用包名与 immortalwrt 不同 | Phase 2 逐步映射（见下） |
| 刷坏 | 长按 Reset 进 MaskROM 重刷即可（BROM 兜底，不会变砖） |

## 7. 阶段计划

- **Phase 1（今晚）**：最小可启动配置 → 验证 u-boot 按键链路（单编断言）→ 全量构建 → 出首版
- **Phase 2**：把 immortalwrt 的 566 个包按 iStoreOS feed 名称映射补齐（dockerman、store、HA、EMQX 等）
- **Phase 3**：实机刷入验证（网口/USB/PCIe/温度/key 刷机），出验收报告
