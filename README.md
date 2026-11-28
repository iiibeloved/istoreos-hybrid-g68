# NSY G68-PLUS · iStoreOS 杂交固件（swconfig 版）

[![构建状态](https://github.com/iiibeloved/istoreos-hybrid-g68/actions/workflows/build.yml/badge.svg)](https://github.com/iiibeloved/istoreos-hybrid-g68/actions/workflows/build.yml)
[![最新 Release](https://img.shields.io/github/v/release/iiibeloved/istoreos-hybrid-g68)](https://github.com/iiibeloved/istoreos-hybrid-g68/releases/latest)

> 一句话简介：给 **农商云 NSY G68-PLUS（RK3568）** 用的完整 iStoreOS 固件，保留官方全部应用生态，并加入**长按 Reset 直接进 MaskROM** 的刷机体验；网络采用久经真机验证的 **RTL8367S / swconfig（4 个 LAN + 1 个 WAN）** 方案。

如果你是第一次接触本固件，建议只看下面四节即可完成刷机：**[固件特点](#二固件特点) → [刷机前注意事项](#四刷机前注意事项) → [刷机方法](#五刷机方法) → [刷机后注意事项](#六刷机后注意事项)**。其余章节是进阶说明。

---

## 目录

- [一、这是什么](#一这是什么)
- [二、固件特点](#二固件特点)
- [三、包含内容](#三包含内容)
- [四、刷机前注意事项](#四刷机前注意事项)
- [五、刷机方法](#五刷机方法)
- [六、刷机后注意事项](#六刷机后注意事项)
- [七、下载与校验](#七下载与校验)
- [八、已知限制](#八已知限制)
- [九、常见问题](#九常见问题)
- [十、技术实现（进阶）](#十技术实现进阶)
- [十一、本地构建](#十一本地构建)
- [致谢](#致谢)

---

## 一、这是什么

本固件面向 **RK3568 架构的 G68-PLUS 软路由 / NAS 小板**，把两套经过验证的成果合在一起：

| 组成 | 来源 | 带来的好处 |
| --- | --- | --- |
| **系统基座** | [iStoreOS 24.10 官方](https://github.com/istoreos/istoreos)（`istoreos-24.10`） | 内核 6.6、官方软件源、完整应用生态，随上游持续更新 |
| **设备适配层** | NSY G68 真机验证的 DTS / u-boot / 分区 / 按键配置 | 长按 Reset 进 MaskROM、5 口千兆、eMMC 分区布局 |
| **网络方案** | RTL8367S + `swconfig` 驱动 | 4 LAN + 1 WAN， DHCP 与 LAN/WAN 开箱即用 |

它**不是裁剪版**：iStoreOS 商店、Docker、文件共享、下载工具等一应俱全。设备适配以“整文件 overlay”方式注入，不在 iStoreOS 上游维护长期分叉，因此上游升级时冲突面最小。

> 需要 **DSA 网络栈**（`lan1`~`lan4` / `wan` 独立网口）而不是 swconfig 的用户，请使用姊妹仓库 [istoreos-hybrid-g68-dsa](https://github.com/iiibeloved/istoreos-hybrid-g68-dsa)。

---

## 二、固件特点

- **刷机省心：长按 Reset 就能进 MaskROM。** 上电时按住 Reset 键即可被 RKDevTool 识别，无需拆机短接测试点；刷写方式与 immortalwrt 固件一致（USB 双公头 + RKDevTool + 强制按地址写）。
- **5 口全千兆，开箱就能上网。** RTL8367S 交换芯片由 `swconfig` 驱动正确初始化，划分为 **4 个 LAN 口 + 1 个 WAN 口**；LAN 口 DHCP、WAN 口 DHCP 客户端默认可用，插上网线即可获取地址。
- **完整 iStoreOS 生态。** 商店、初始化向导、Docker、SMB 共享（`samba4` / `ksmbd`）、WebDAV（`unishare` / `webdav2`）、NFS、文件管理 / 传输、定时控制、上网行为管理等应用全部内置，不是精简固件。
- **稳定可升级、可重复构建。** 每次构建以 iStoreOS 官方包清单为基准去重：同名 / 同文件的第三方包一律让位；滚动 feed 锁定到已验证提交、同名包生效来源统一指定、编译前做全包依赖版本校验，防止上游静默漂移导致“这次能编、下次编不过”。
- **核心功能有“双阶段 fail-fast”守卫。** 上游更新自动重建，但网络生命线包（swconfig 四件套 + dnsmasq-full）、蜂窝能力移除（32 个蜂窝包不得出现，SMSC 网络驱动不得误禁）与长按进 MaskROM 链路在 **defconfig 展开后** 和 **最终镜像 manifest** 各校验一次，缺一 / 带回蜂窝即停止构建 / 禁止发布；DTS、u-boot overlay、板级网络映射全部以整文件 overlay 投递并逐字节比对，上游改同名文件也盖不掉本机的网络与按键行为（详见[10.6 上游更新不变量](#106-上游更新不变量如何被守住)）。
- **中文界面到位，不留孤儿菜单。** 仅当对应应用确实安装时才覆盖其中文界面，不会出现“装了中文包但菜单不存在”的空项。
- **完整生态含 Go 应用。** DDNS-Go、Lucky 等要求较新 Go 版本的应用已随固件编译提供；构建侧通过 `GOTOOLCHAIN=auto` 与单线程重试兜底消除工具链竞态（见「技术实现」）。
- **多重自动化守卫。** 每次构建前做静态自检、硬件级交叉审核（DTS ↔ 内核配置 ↔ 包集），并对 u-boot 做源码 / 应用后 / 编译产物三层断言，防止 MaskROM 与网络能力被上游改动悄悄破坏。

---

## 三、包含内容

### 3.1 主要软件

| 类别 | 代表组件 |
| --- | --- |
| 商店 / 向导 | `luci-app-store`（iStore 商城）、`luci-app-quickstart`（首页与网络向导） |
| 容器 | `dockerd`、`containerd`、`runc`、`luci-app-dockerman` |
| 文件共享 | `samba4-server` + `luci-app-samba4`、`ksmbd-server` + `luci-app-ksmbd`（SMB）、`unishare`、`webdav2`、`nfs-kernel-server` |
| 网盘 / 下载 | `lucky` + `luci-app-lucky`、`luci-app-fileassistant`、`luci-app-filemanager`、`luci-app-filebrowser`、`luci-app-filetransfer` |
| 网络 / DNS | `dnsmasq-full`（DNS + DHCP）、`firewall4`、`netifd`、`luci-app-openclash` / `luci-app-passwall` / `luci-app-homeproxy` |
| 系统 / 管控 | `luci-app-diskman` + `smartmontools`（磁盘健康）、`luci-app-timecontrol`、`luci-app-control-webrestriction`、`luci-app-control-weburl`、`luci-app-wolplus`、`luci-app-argon-config` |
| 其他 | `luci-app-ddns-go`、内网穿透等 iStoreOS 生态应用 |

> SMB 共享出厂默认启用 `samba4`、不自启 `ksmbd`（两者都监听 TCP 445，同时自启会争用端口），详见[刷机后注意事项](#六刷机后注意事项)。
>
> 完整且权威的清单是每次 Release 附件中的 **`packages.manifest`**（含依赖展开，数量随每次构建与上游变化）。本表只列代表组件：配置文件直接选中约 **740** 项，依赖展开后更多；一律以该 manifest 为准。

### 3.2 网口与网络

| 逻辑接口 | 硬件端口 | 角色 |
| --- | --- | --- |
| `lan`（br-lan） | RTL8367S port 0~3 | 4 个 LAN 口，同一网桥，硬件二层转发，DHCP 服务端 |
| `wan` | RTL8367S port 4 | 1 个 WAN 口，DHCP 客户端（可改 PPPoE） |
| CPU 上联 | port 6u → `eth0`、port 7u → `eth1` | 交换芯片与 SoC 的两条上联 |

- 物理网口编号与逻辑口（LAN/WAN）的对应以刷机后实测为准（见 [刷机后注意事项](#六刷机后注意事项)）。
- 面板上的 2.5G 标识口实际按 SGMII **1000 Mb/s** fixed-link 工作（真机实测），不是 2500 Mb/s。

### 3.3 分区布局

| 分区 | 大小 | 用途 |
| --- | --- | --- |
| `uboot` | 16 MiB | u-boot / SPL |
| `kernel` | 16 MiB | 内核 + DTB（FIT 镜像） |
| `rootfs` | 500 MiB | 只读 squashfs 系统 |
| `rootfs_data` | 4096 MiB | 可写 overlay（配置、iStore / opkg、Docker 数据） |

> 升级镜像约 **100 MiB**（squashfs 压缩后）；`rootfs_data` 文件系统在首次启动时自动创建。

---

## 四、刷机前注意事项

1. **准备工具**：双公头 USB 数据线、`RKDevTool_Release_v3.18`、驱动 `Rockchip_DriverAssitant_v5.12`，以及**解压成 `.img` 的固件**（刷机工具不认 `.img.gz`）。
2. **核对文件**：下载后用 `sha256sum -c sha256sums` 校验镜像，不一致请重新下载。
3. **备份配置**：旧系统还能进入时，先在 LuCI「系统 → 备份/升级」导出配置备份。
4. **接对 USB 口**：用靠近网口一侧的 **USB OTG 口**连接电脑。
5. **保证供电**：刷写与首次启动期间**不要断电**，eMMC 写入中断最难恢复。
6. **理清网口角色**：本固件是 **4 LAN + 1 WAN**；刷机后需按实测确认哪个口是 WAN，再把上级路由 / 光猫接到 WAN 口（见第六节）。
7. **管理地址预期**：默认网关为 **`192.168.100.1`**（iStoreOS 基座默认，已真机验证；若与局域网冲突，以电脑实际获取到的默认网关为准，首次向导中可修改）。

---

## 五、刷机方法

系统能否进入，选择对应方式：

### 5.1 系统还能进 → 在线升级

```
LuCI → 系统 → 备份/升级 → 上传 .img.gz → 勾选「保留配置」（如需清空则不勾）→ 执行
```

### 5.2 首次刷写 / 进不去系统 → MaskROM（USB 刷机）

1. 电脑安装驱动 `Rockchip_DriverAssitant_v5.12`，打开 `RKDevTool_Release_v3.18`。
2. 设备**断电**，双公头 USB 线连接电脑与设备 OTG 口。
3. **按住 Reset 键不松开 → 接通电源 → 待 RKDevTool 提示“发现一个 MaskROM 设备”后松开 Reset。**
   - 若长按无效，可用拆机短接测试点的传统方式兜底（loader 相同）。
4. 「高级功能」→ 加载 `rk356x_spl_loader_v1.21.113.bin`。
5. 「获取当前存储」→「**擦除所有**」，进度到 100% 才算成功（若“秒擦除”，需检查 eMMC）。
6. 「下载镜像」→ 选择**解压后的 `.img`** → **勾选「强制按地址写」** → 点击「执行」，等到 100% 成功。
7. 完成后断开 USB、重新上电，接好网线。

> **“强制按地址写”必须勾选**，否则可能写入不完整或校验失败。

---

## 六、刷机后注意事项

### 🔧 刷机后复位键的正确用法（新版本已修复）

本版本已把 DTS 里复位键的映射从 `KEY_F12` 修正为 `KEY_RESTART`（`label = "reset"`），**系统运行时长按复位键现在可以正常恢复出厂**。同一个物理按键在两个阶段的作用完全不同，请勿混淆：

| 场景 | 操作 | 结果 |
|---|---|---|
| **刷机进 MaskROM** | **断电 → 按住 Reset 不松开 → 通电**，待 RKDevTool 识别到设备后再松开 | 进入 MaskROM，用 USB 刷机（见[第五节](#五刷机方法)）。这是 U-Boot 上电瞬间独立采样，**不经过内核** |
| **系统运行时 · 短按** | 点按复位键（小于 1 秒即松开） | 普通重启，**保留全部配置** |
| **系统运行时 · 按住约 5 秒** | 按住不松开约 5 秒 | 进入 **failsafe 安全模式**（保留配置，可用于救援） |
| **系统运行时 · 长按 ≥ 5 秒** | 按住 5 秒以上再松开 | **恢复出厂设置**：执行 `firstboot -y && reboot`，清空配置并自动重启，首次启动需再等 1~3 分钟 |

> **说明**
> - 恢复出厂只清除用户配置（`/overlay`），**不会抹掉固件本身，也不会退回旧版本**；完成后需重新走初始化设置。
> - 旧版固件因 DTS 把该键映射为 `KEY_F12`，系统运行时按复位键**没有任何反应**；新版本已修复，并在 `scripts/selftest.sh` 加了正向 + 反向守卫（必须为 `KEY_RESTART`、禁止 `KEY_F12` 残留），防止上游更新把它改回去。
> - **MaskROM 与恢复出厂互不冲突**：前者是上电瞬间 U-Boot 的行为，后者是 Linux 系统运行时的行为；因此刷机流程（第五节）保持不变。
> - 判断依据见 `/etc/rc.button/reset`：`SEEN < 1` 重启、`SEEN ≥ 5` 执行 `firstboot -y && reboot`。

> 本节是新旧版本差异最容易被忽略的地方，请按序号操作。

1. **耐心等待首次启动（约 1~3 分钟）。** 首次开机会创建 `rootfs_data` 文件系统并执行初始化脚本，期间网口灯可能闪烁、页面暂时打不开，属正常现象；**不要在此阶段断电或反复重启**。
2. **进入初始化向导。** 浏览器访问默认网关（通常 **`http://192.168.100.1`**，或在电脑命令行执行 `ipconfig` / `route -n` 查看默认网关）→ 按 iStoreOS 向导完成设置，并**第一时间修改 root 密码**。
3. **先确认 LAN，再接 WAN。**
   - 电脑接任意 LAN 口，应能自动获取 `192.168.100.x` 地址并打开管理页——**能打开管理页，说明交换机驱动、用户态 `swconfig`（应用 VLAN）与 LAN/DHCP 都已正常工作**（旧版“只能当交换机、拿不到 IP”的问题即出在此环节，新固件已修复；若新版仍拿不到 IP，按[第九节 FAQ](#九常见问题) 的 `swconfig` 排查项核对 `packages.manifest`）。
   - 再把上级路由 / 光猫的网线接到 **WAN 口**，WAN 默认 DHCP 获取地址；如需 PPPoE，在网络 / 向导中改为拨号并填入账号密码。
4. **核对网口物理对应。** 逐一插拔网线，确认哪个口是 WAN、哪些是 LAN，并在网络接口页观察连接状态；LAN 口之间应能互相通信，WAN 口不应出现在 br-lan 网桥中。
5. **验证外网与软件源。** 在“系统 → TTYD / SSH”执行 `ping -c3 223.5.5.5 && opkg update`，全通即表示网络与软件源正常。
6. **验证 MaskROM 能力（可选）。** 下次需要刷机时，用第五节的长按 Reset 流程验证一次即可；平时不必反复进 MaskROM。
7. **完成配置后备份。** 系统 → 备份/升级 → 生成配置备份并妥善保存，便于日后恢复。
8. **SMB 服务默认已配好，开箱即用。** 固件内置 `samba4-server` 与 `ksmbd-server` 两套 SMB 服务端，二者都监听 TCP **445** 端口，同时自启会争用端口。已通过首次启动脚本默认**启用 samba4、禁用 ksmbd 自启**，无需手动干预即可使用 SMB 共享。若确需改用 ksmbd：在「系统 → 启动项」中禁用 `samba4`、启用 `ksmbd` 并重启即可，SMB 文件共享功能本身不受影响。
9. **菜单说明**：首页（QuickStart）固定为左侧第一项，网络向导（NetworkGuide）紧随其后；独立的“设置向导”（`luci-app-netwizard`）与多余的“管理面板”（Dashboard）已移除，不影响网络向导配网功能；服务菜单中 `wol` 显示为“网络唤醒”、`wolplus` 显示为“网络唤醒++”，便于区分。**蜂窝能力已整体移除**：`configs/g68-hybrid.config` 显式关闭全部 32 个蜂窝 / 短信 / 拨号包（`luci-app-sms-tool`、`luci-app-modem`、`modemmanager`、`luci-proto-*`、`libqmi`/`libmbim`、`uqmi`/`umbim`、`wwan`、`quectel-CM-5G` 等），固件不含任何 4G/5G/短信功能；`menu.d` 覆盖 + 首次启动脚本注释 controller 作为纵深兜底，防止上游意外带回时 Modem 菜单露出。**注意**：`kmod-phy-smsc` / `kmod-usb-net-smsc95xx` 是 SMSC 以太网 PHY 驱动（名字含 sms 但与蜂窝无关），予以保留并由守卫反向锁定。服务菜单中两个“网络共享”已区分：`samba4` 显示为“网络共享++”，`ksmbd` 保持“网络共享”。
10. **常见误区**：
   - 只接了 LAN 口、没接 WAN → 能进管理页但上不了外网，属正常，接好 WAN 即可。
   - 上级路由 LAN 口与本机 LAN 同为 `192.168.100.x` → 地址冲突，先在向导里把本机 LAN 改到其它网段。
   - 面板 2.5G 标识口按 1000 Mb/s 工作 → 规格如此，不是故障。

---

## 七、下载与校验

- **最新 Release**：<https://github.com/iiibeloved/istoreos-hybrid-g68/releases/latest>
- 版本号、镜像与校验值**以 Release 页面为准**（本仓库会持续更新，本文不写死版本号与哈希，避免过期）。

| 资产 | 说明 |
| --- | --- |
| `istoreos-rockchip-armv8-nsy_g68-plus-squashfs-sysupgrade.img.gz` | 固件镜像（约 100 MiB，刷机前需解压） |
| `sha256sums` | 镜像校验值 |
| `packages.manifest` | 本次构建完整包清单（含依赖展开，以 Release 附件为准） |

**国内加速**（把 `<tag>` 和 `<file>` 替换为实际版本号与文件名，`https://` 后拼接以下前缀）：

- `https://gh-proxy.com/https://github.com/iiibeloved/istoreos-hybrid-g68/releases/download/<tag>/<file>`
- `https://ghfast.top/https://github.com/iiibeloved/istoreos-hybrid-g68/releases/download/<tag>/<file>`
- `https://ghproxy.net/https://github.com/iiibeloved/istoreos-hybrid-g68/releases/download/<tag>/<file>`

---

## 八、已知限制

- **不使用 WiFi**：G68 的 MT7916 未启用（WiFi 栈整体不选），需要无线请另行方案。
- **DNS/DHCP 用 `dnsmasq-full`**：与 `dnsmasq` 互斥，二者只能选其一。
- **SSL 栈为 mbedtls**：不选 `luci-ssl-openssl`（会与基座 `libustream-mbedtls` 冲突）。
- **2.5G 口实为 1000 Mb/s**：SGMII fixed-link 真机实测值。
- **需真机验收**：LAN/WAN、eMMC/USB、长按 Reset、中文界面与商城建议实机逐项确认。

---

## 九、常见问题

| 现象 | 处理 |
| --- | --- |
| 刷机后只能当交换机、拿不到 IP、无 WAN | 依次确认 Release 的 `packages.manifest`：① 三个内核驱动 `kmod-switch-rtl8367b` / `kmod-switch-rtl8366-smi` / `kmod-swconfig`；② **用户态 `swconfig`（关键）**——它安装 `/lib/network/switch.sh`，由 `init_switch()` 执行 `swconfig dev switch0 load network` 把 UCI 里的 VLAN 分组真正写入 RTL8367S。**只有 kmod 而缺用户态 `swconfig` 时，VLAN 分组不会生效，同样拿不到 IP**（旧版即此问题）。③ 若以上齐全仍拿不到 IP，多为 SGMII CPU 上联未编程 MAC select（内核补丁 `915`）——判别方法：串口下 `ping -I br-lan -c 5 <同网段地址>` 后对比 `ip -s link show eth0` 的 TX 与 `swconfig dev switch0 port 6 get mib` 的 `ifInOctets`，**TX 增长但 port6 的 `ifInOctets` 恒为 0 即可确诊**。本固件已包含该修复。任一项缺失都需重刷带修复的新版 |
| 能进管理页但上不了外网 | 检查 WAN 口是否接了上级路由 / 光猫；WAN 是否为 DHCP；上级 LAN 是否与本机能正常连通 |
| 管理页打不开 | 用 `ipconfig` 查电脑默认网关再访问；或确认处于同网段；首次启动请等 1~3 分钟 |
| RKDevTool 找不到 MaskROM 设备 | 检查驱动、USB 线（须为数据线）与 OTG 口；长按 Reset 时序或改用短接触点法 |
| 刷机中途报错 / 校验失败 | 重新“擦除所有”后勾选“强制按地址写”再刷；核对 sha256 |
| 商城 / quickstart 无中文 | 确认对应应用已安装后重启（中文为条件投递） |
| 服务菜单里找不到 Modem / Cellular Network | 这是刻意移除的：编译期已显式关闭全部蜂窝 / 短信 / 拨号包，固件不含任何蜂窝能力；`menu.d` 覆盖与首次启动脚本仅作纵深兜底。如需 4G/5G 请另刷带蜂窝的版本 |
| 服务里两个“网络共享”分别是什么 | “网络共享++”是 samba4，“网络共享”是 ksmbd；默认启用 samba4、关闭 ksmbd 自启，二者共用 445 端口不可同时自启 |
| 上游 iStoreOS 更新后会不会把 LAN / 长按进 MaskROM 改坏 | 不会静默改坏：上游变更会自动触发重建，但网络生命线包在 defconfig 后和最终 manifest 各校验一次、DTS/u-boot overlay/网络映射逐字节比对、MaskROM 做源码/应用/产物三层断言，任一关键项漂移即 fail-fast 阻断构建，不会发布带病固件 |

---

## 十、技术实现（进阶）

### 10.1 为什么叫“杂交”（Hybrid）

不在 iStoreOS 里维护长期分叉的内核 / 设备树；设备层以**整文件 overlay** 交付，上游升级时冲突面最小。

### 10.2 关键机制

- **长按 Reset → MaskROM**：SPL 阶段读 SARADC 通道 0；按住 Reset 上电即写 BROM 下载标志并复位，RKDevTool 直接识别 MaskROM 设备。u-boot 以 overlay-only 覆盖 `src/`，并由三层断言（`download key pressed` / `adc_channel_single_shot` / `BOOT_MODE_REG=0xfdc20200`）守护。
- **官方基准去重**：每轮构建以官方 defconfig / manifest 为唯一基准，同名 / 同文件 / PROVIDES 冲突项自动注释并回写，保证上游更新后重建可预期。
- **Feed 防漂移（fail-fast）**：滚动 feed 锁到已验证提交（`configs/feeds.lock`），同名包的生效来源统一声明（`configs/feed-precedence.txt`，如 `sing-box` 固定取 `small`）；构建时用 `feed-pin.sh` 固定提交、`feed-sources.sh` 删除其他 feed 的同名链接并重装校验，`dep-guard.sh` 在 `make defconfig` 后遍历所有选中包的版本化依赖做秒级校验。上游 packages 的旧版 `sing-box` 抢占链接、HomeProxy 要求 `>=1.15.0_alpha10` 导致“编译 3 小时后才失败”的问题因此被提前拦截。
- **只交付 squashfs**：`configs/g68-hybrid.config` 显式关闭 `CONFIG_TARGET_ROOTFS_EXT4FS`、保留 `CONFIG_TARGET_ROOTFS_SQUASHFS=y`，并在 `make defconfig` 后二次压回校验；收集产物时拒绝任何 `*-ext4*.img.gz`。ext4 不压缩（未压缩 rootfs 树约 691 MiB，塞不进 500 MiB 分区），squashfs 压缩后约 100 MiB，故只发布 squashfs 镜像。
- **Go 工具链放宽**：`ddns-go` / `xray` / `sing-box` 等 small feed 的 Go 包要求 Go >= 1.25（早期失败日志：`go: go.mod requires go >= 1.25.0 (running go 1.23.12)`）。`build.yml` 把 `feeds/packages/lang/golang/` 内的 `GOTOOLCHAIN=local` 统一替换为 `auto`，让各包自动获取匹配工具链，并保留「并行编译失败 → `-j1 V=s` 单线程重试」兜底，规避多包并发下载工具链的竞态。
- **文本文件行尾固定为 LF（自检强制）**：`scripts/*.sh`、`configs/*.config`、`.github/workflows/*.yml` 与 `device/files/` 下的脚本必须全部以 LF 存储；`selftest.sh` 第 0.5 节在编译前逐文件扫描 CR 字符并阻断构建。历史上两类事故均由 CRLF 引起：`configs/g68-hybrid.config` 被写成 CRLF 时，行尾 `\r` 让 `grep -qx "CONFIG_PACKAGE_xxx=y"` 全项误报、`make defconfig` 静默丢符号；`scripts/dep-guard.sh` 被写成 CRLF 时，dash 把 `set -u\r` 解析为 `Illegal option`，build 作业在进入编译前直接退出。注意：通过 Git Data API 直接创建 blob 会绕过 git 客户端的行尾规范化，提交前务必核对远程 blob 的真实行尾。
- **中文条件投递**：`g68-i18n` 仅在检测到对应应用已安装时覆盖界面文件。
- **CI 硬件审核**：`hw-audit` 交叉核对 DTS ↔ 内核配置 ↔ 包集（RTL8367S / XPCS / adc-keys / 存储 / WiFi 豁免），缺关键项阻断构建。
- **核心网络包 + 蜂窝移除双阶段守卫**：`scripts/verify-critical.sh` 在 `build` 作业里跑两次——`make defconfig` 之后查真实 `.config`，收集产物时再查最终 `packages.manifest`。两个阶段都做两类断言：① 网络生命线（swconfig 四件套 + dnsmasq-full）必须齐全，缺一秒级失败 / 禁止发布；② 32 个蜂窝包必须全部未选中 / 未进产物，任一被上游 feed 漂移或去重重新带入即失败，同时反向锁定 SMSC 以太网 PHY 驱动不被误禁。`selftest.sh` §14 复用同一守卫在 config 输入阶段先查一次（清单只维护一份，避免漂移），并断言调用点与脚本本身存在，防止守卫被误摘。
- **网络链路应用后守卫（补丁生效验证）**：`scripts/verify-network.sh` 解决"包齐全但网络死"的盲区。上游每次增量提交都可能改动 `dwmac-rk.c` / rk3568 dts 的上下文，使内核补丁 hunk 静默 FAILED——历史事故 `c6d9bc6` 即 915 补丁 hunk 失败后编译仍"成功"、刷入后 LAN 拿不到 IP。`verify-network.sh source` 在编译后检查打过补丁的内核源码确实含 910（SGMII 支持）、913（fixed-link 强制速率）、915（`pipe_grf` 成员 + `PIPE_GRF_XPCS_SGMII_MAC_SEL` 编程 + `pipegrf` phandle 读取）与 RTL8367S 驱动 overlay；`verify-network.sh dts` 在 prepare 与产物两阶段检查板级 DTS 的 `sgmii-mac-sel`/`pipegrf`/`phy-mode=sgmii`/RTL8367S switch/xpcs 节点。任一锚点缺失即禁止发布。`selftest.sh` 断言脚本存在且 build.yml 挂载点齐全，防被误摘。
- **蜂窝能力整体移除 + Modem 菜单纵深兜底**：主动防线在编译期——`configs/g68-hybrid.config` 用 `# CONFIG_PACKAGE_x is not set` 显式关闭 32 个蜂窝包，由 `verify-critical.sh` 两阶段守卫锁定（见上）。菜单层是纵深兜底：顶级 Modem（带“短信”子项）原是 `luci-app-sms-tool` controller 的 `entry({"admin","modem"}, ...)`，状态页 Cellular Network 原是 `luci-proto-modemmanager` 的 `admin/status/modemmanager`；`zz-hide-modem.json` 用 `menu.d` 后加载覆盖 + `depends.fs` 恒假隐藏这两个节点（`zz-` 排序在 `luci-` 之后）。但 LuCI `build_pagetree` 按 glob 顺序在 menu.d 之后处理 controller/*.lua，且每个文件都会重算 `node.satisfied`，sms.lua 的顶级 entry 无 depends 会把覆盖重算为 true；因此首次启动脚本 `91-g68-hide-modem-entry` 幂等地把该 entry 注释为 Lua 注释，两者配合才真正隐藏（真机 indexcache 实测 `satisfied=false`）。正常固件里这些 controller 随蜂窝包一起不存在，兜底只在上游意外带回时生效。**反向依赖坑（2026-11-23）**：上游 `comgt-ncm` 的 `DEPENDS:=+wwan`、`kmod-usb-serial-option/ipw/qualcomm` 的 `AddDepends(...,+kmod-usb-serial-wwan)`、`luci-proto-ncm` 的 `LUCI_DEPENDS:=+comgt-ncm`、`quectel-timesync` 的 `DEPENDS:=+kmod-usb-serial-option` 会在 `make defconfig` 时把已禁用的末端蜂窝包强制 select 回 `=y`。因此这 10 个源包也必须显式关闭并纳入清单（对全部 feed 的 Makefile 做过反向依赖全量扫描）；仅禁用末端包会导致守卫在 defconfig 阶段 fail-fast（r2 之后的构建曾两次因此中止）。
- **Samba4 标签区分**：`zz-samba4-label.json` 把 `admin/services/samba4` 的 title 覆盖为“网络共享++”，与 `ksmbd` 的“网络共享”区分（两个 SMB 服务都装、共用 445，默认启用 samba4）。

### 10.3 构建流水线

```text
iStoreOS 官方源 (istoreos-24.10)
   │ clone
   ▼
apply-device.sh ──► 设备层注入（DTS / u-boot overlay / 内核补丁 / 分区 / i18n）
   ▼
selftest.sh ──► 静态自检（0.5 行尾守卫 / overlay / defconfig / 补丁 / DTS / 镜像定义）
   ▼
hw-audit.sh ──► 硬件级审核（DTS ↔ kernel-config ↔ 包集 ↔ u-boot defconfig）
   ▼
package-guard ──► 以官方清单为基准去重（同名 / 同文件 / PROVIDES）
   ▼
uboot-check ──► feed-pin 固定提交 → 只编译 u-boot + 三层产物断言
   ▼
build ──► feed-pin 锁定滚动 feed → feed-sources 固定同名包来源
          → defconfig → 关闭 ext4 / 保留 squashfs → dep-guard 依赖版本守卫
          → verify-critical(config) 核心网络包 + 蜂窝移除守卫（缺包/带回蜂窝秒级失败）
          → 全量编译 → 仅收集 squashfs 镜像 → 分区表校验
          → verify-critical(manifest) 产物包 + 蜂窝移除守卫（缺包/带回蜂窝禁止发布）
          → artifact → Release → 回写 state 锁
```

| 作业 | 职责 |
| --- | --- |
| `check-upstream` | 对比上游 commit 与 `state` 锁，决定是否构建 |
| `prepare` | 应用设备层、静态自检、硬件审核、官方基准去重 |
| `uboot-check` | `feed-pin` 固定提交后独立编译 u-boot，验证 MaskROM 链路 |
| `build` | 固定 feed 提交与同名包来源、defconfig 归一化（关闭 ext4）、依赖版本守卫、核心网络包双阶段守卫、全量编译、**网络链路补丁生效守卫（source+dts）**、仅接受 squashfs 镜像并校验、发布 Release、回写 `upstream.lock` |

触发方式：`push`（配置变更）、`workflow_dispatch`（手动）、`schedule`（每周检查）、`upstream-watch`（上游变化自动触发）。

### 10.4 仓库结构

```text
device/
  kernel-dts/            G68 内核设备树（SGMII/XPCS、RTL8367S、adc-keys、eMMC）
  kernel-config          内核配置片段（SWCONFIG / RTL8366_SMI / RTL8367B_PHY）
  kernel-files/          内核驱动覆盖（支持 RTL8367S 的 rtl8367b 等，仅内核 6.6）
  board.d/               板级网络映射 02_network_g68（不改上游 02_network）
  kernel-patches/        910/911/913/914/915 内核补丁（915=SGMII MAC select 修复 LAN 拿不到 IP）
  uboot/                 u-boot overlay（boot_mode、defconfig、板级 dts、版本守卫）
  i18n-overlay/          中文覆盖（条件投递）
  files/                 落盘配置与 LuCI 菜单覆盖（zz-hide-modem.json + 91-g68-hide-modem-entry 隐藏 Modem，zz-samba4-label.json 区分网络共享）
  hw-exemptions.txt      硬件豁免清单（如 WiFi）
scripts/                 apply / selftest / hw-audit / verify-maskrom / verify-critical / package-guard 等
  feed-pin.sh            按 feeds.lock 固定滚动 feed 提交（防 main 漂移）
  feed-sources.sh        按 feed-precedence.txt 固定同名包的生效来源
  dep-guard.sh           defconfig 后全包依赖版本一致性守卫（fail-fast）
  verify-critical.sh     核心网络包 + 蜂窝移除双阶段守卫（defconfig 后 + 最终 manifest）
  verify-network.sh      网络链路应用后守卫（编译后补丁 hunk 生效 + 板级 DTS 锚点）
configs/
  g68-hybrid.config      完整包配置（含目标 / 设备 / 分区，显式关闭 ext4 rootfs）
  feeds.lock            滚动 feed 的已验证提交
  feed-precedence.txt   同名包生效来源优先级
.github/workflows/       build / maskrom-guard / package-guard / upstream-watch
```

### 10.5 不变量（任何改动都不得破坏）

1. 长按 Reset → MaskROM 链路可用（三层守卫通过）；
2. 包集以 iStoreOS 官方为基准去重；
3. 滚动 feed 锁到已验证提交、同名包来源固定、依赖版本守卫通过（防静默漂移）；
4. 仅交付 squashfs 镜像，ext4 rootfs 始终关闭；
5. 中文条件投递，不产生孤儿菜单；
6. 全量包集（非裁剪版），WiFi 除外；
7. 上游只认 iStoreOS，设备层以 overlay 交付。
8. **文本文件行尾 = LF**：`configs/*.config`、`scripts/*.sh`、workflow 与 `device/files/` 下脚本必须全部以 LF 存储，由 `selftest.sh` 第 0.5 节逐文件扫描 CR 并阻断构建（CRLF 会让 `grep -qx` 自检、`make defconfig` 与 `/bin/sh` 的 `set` 指令失效）；
9. **核心网络包双阶段守卫通过**：defconfig 展开后的 `.config` 与最终 `packages.manifest` 都必须含 swconfig 四件套 + dnsmasq-full；
10. **蜂窝能力保持整体移除 + Modem 菜单隐藏**：config 中 32 个蜂窝包必须全部为 `is not set`（`verify-critical.sh` 两阶段守卫拦截重新引入），SMSC 以太网 PHY 驱动必须保留；`zz-hide-modem.json`（含 `admin/modem` 顶级节点）与 `91-g68-hide-modem-entry` 作为兜底必须投递且内容不被破坏；`zz-samba4-label.json` 保证 Samba4 标签为“网络共享++”。
11. **内核补丁必须真实生效**：编译后打过补丁的 `dwmac-rk.c` 必须含 910/913/915 的应用后代码，板级 DTS 必须含 `pipegrf`/`sgmii-mac-sel`。包齐全 ≠ 网络可用（历史事故：补丁 hunk 静默失败导致刷入后 LAN 全瘫）。

### 10.6 上游更新不变量如何被守住

`upstream-watch` 每小时比对 iStoreOS `istoreos-24.10` 分支 commit，发现更新即自动触发全量重建。上游改动**不会静默覆盖**本机的网络与 MaskROM 能力，靠的是下面几层守卫；任一层失败即阻断构建、不放行带病 Release：

| 不变量 | 投递方式（为何不被覆盖） | 守卫（何时拦截） |
| --- | --- | --- |
| **网络映射**（4 LAN + 1 WAN，port 6u→eth0 / 7u→eth1） | 独立 `board.d/02_network_g68`，按字母序排在上游 `02_network` **之后**加载；不改上游文件 | `selftest` §7 逐字节比对 + 语法 / 双上联断言；上游改 `02_network` 不影响本文件 |
| **RTL8367S 驱动** | `device/kernel-files/generic/` 整文件 overlay 覆盖上游 `rtl8367b.c` 等 | `selftest` §6 逐字节比对 + `realtek,rtl8367s` 关键字；内核版本非 6.6 时 `apply-device.sh` 直接失败 |
| **VLAN 落地**（用户态 `swconfig`） | config 明确选中 + package-guard `--allow swconfig` 豁免去重 | `selftest` §6 查 config 输入；`verify-critical.sh` 在 defconfig 后与 manifest 各查一次真实包集 |
| **SGMII MAC select**（915 补丁，修 LAN 拿不到 IP） | `device/kernel-patches/915-*.patch` 随每次构建投递 | `selftest` §2 补丁投递齐备 + §1 DTS 锚点；`verify-network.sh source` 编译后确认 `dwmac-rk.c` 真含 `pipe_grf` + `PIPE_GRF_XPCS_SGMII_MAC_SEL` + `pipegrf` 读取（hunk 静默失败即刻阻断，历史事故 c6d9bc6 不再重演）；`dts` 模式确认 `sgmii-mac-sel`/`pipegrf` phandle |
| **长按 Reset → MaskROM** | u-boot overlay-only（4 文件整文件覆盖 + 版本锁 `OVERLAY_BASE`），不用 patch | `verify-maskrom.sh` 三层断言：repo 内容 / 应用后源码树 / 编译产物二进制字符串 + `.config` 寄存器 |
| **DNS 唯一性**（dnsmasq-full 替代 dnsmasq） | config 显式二选一 | `selftest` §10 + defconfig 检查 + `verify-critical.sh` 三处确认互斥 |
| **蜂窝能力整体移除**（用户决策，不含 4G/5G/短信） | config 显式关闭 32 个蜂窝包（`is not set`） | `selftest` §14 + `verify-critical.sh` 在 defconfig 后与 manifest 各查一次：任一蜂窝包重新出现即失败，同时反向锁定 SMSC 以太网 PHY 驱动不被误禁 |

> 换言之：上游更新只会带来"重新构建并复验"，任何会让 LAN/WAN 或长按进 MaskROM 失效、或把蜂窝能力带回的变化都会在中途 fail-fast，而不是产出一个刷入后拿不到 IP 或带多余蜂窝应用的固件。若上游升级 u-boot 或内核大版本，`apply-device.sh` 的版本守卫会主动报错停下，提示基于新版本重新移植 overlay——绝不带病构建。

---

## 十一、本地构建

```sh
git clone --depth 1 -b istoreos-24.10 https://github.com/istoreos/istoreos.git
sh scripts/apply-device.sh istoreos          # 注入设备层
sh scripts/selftest.sh istoreos              # 静态自检
sh scripts/hw-audit.sh                       # 硬件审核
cd istoreos
./scripts/feeds update -a
sh ../scripts/feed-pin.sh . ../configs/feeds.lock            # 固定滚动 feed
./scripts/feeds install -a
sh ../scripts/feed-sources.sh . ../configs/feed-precedence.txt # 固定同名包来源
# 配置文件与所有 scripts/*.sh 必须为 LF 行尾：CRLF 会让 grep -qx 自检、make defconfig 与 /bin/sh 失效
cp ../configs/g68-hybrid.config .config
make defconfig
# defconfig 会把 EXT4FS 拉回 y，必须二次压回（自动构建已内置此步）
sed -i -E 's/^CONFIG_TARGET_ROOTFS_EXT4FS=y$/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/' .config
sh ../scripts/dep-guard.sh . ../configs/feed-precedence.txt  # 依赖版本守卫
sh ../scripts/verify-critical.sh config .config              # 核心网络包守卫（defconfig 后）
make -j"$(nproc)"
# 编译后确认内核补丁真实生效（hunk 静默失败会让编译仍成功但 LAN 全瘫）
KDIR=$(ls -d build_dir/target-*/linux-rockchip_armv8/linux-6.6.* | head -1)
sh ../scripts/verify-network.sh source "$KDIR"               # 补丁 hunk 应用后守卫
sh ../scripts/verify-network.sh dts device/kernel-dts/rk3568-nsy-g68-plus.dts
```

产物：`istoreos/bin/targets/rockchip/armv8/*nsy_g68-plus*sysupgrade.img.gz`

---

## 致谢

- [iStoreOS](https://github.com/istoreos/istoreos) —— 系统基座与软件生态
- [immortalwrt](https://github.com/immortalwrt/immortalwrt) —— 设备层参考与真机验证经验
- 所有上游包维护者

> 本项目仅做设备层移植与 CI 编排，固件内容遵循各上游组件许可证。
