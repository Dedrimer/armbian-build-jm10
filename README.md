# Yijiahe JM10-3588 Armbian Build

这个仓库是为 Yijiahe JM10-3588 主控板准备的 Armbian 构建仓库，基于 [Armbian build](https://github.com/armbian/build)。板载 SoC 为 Rockchip RK3588，设备树、内核补丁、U-Boot 补丁和系统初始化逻辑均已放在仓库中。

## 支持范围

- 构建目标：`yjh-jm10-3588`
- SoC：RK3588
- 内核分支：`legacy`（5.10）和 `vendor`（6.1）
- 设备树：`rockchip/rk3588-yjh-jm10.dtb`
- U-Boot 配置：`rk3588_defconfig`
- 默认不构建桌面环境：`FULL_DESKTOP="no"`
- Mesa/VPU 用户空间由上游 `armbian-config` 机制负责，不再启用已删除的 `mesa-vpu` 扩展

JM10 的板卡入口是 [`config/boards/yjh-jm10-3588.csc`](config/boards/yjh-jm10-3588.csc)。构建时必须使用准确的板卡名称 `yjh-jm10-3588`。

## 构建环境

建议在 Debian/Ubuntu x86_64 主机上构建，并准备至少 8 GB 内存和约 50 GB 可用磁盘空间。Armbian 的完整主机依赖和容器构建说明见 [官方开发文档](https://docs.armbian.com/Developer-Guide_Overview/)。

不要用 `sudo ./compile.sh` 启动构建；构建脚本会在需要时调用 sudo。

## 快速构建

进入仓库根目录后执行：

```bash
./compile.sh \
  BOARD=yjh-jm10-3588 \
  BRANCH=vendor \
  RELEASE=noble \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes \
  KERNEL_CONFIGURE=no
```

构建 5.10 legacy 内核时，将 `BRANCH=vendor` 改为 `BRANCH=legacy`：

```bash
./compile.sh \
  BOARD=yjh-jm10-3588 \
  BRANCH=legacy \
  RELEASE=noble \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes \
  KERNEL_CONFIGURE=no
```

生成的镜像和构建日志位于 `output/images/` 和 `output/logs/`。第一次构建会下载内核、U-Boot 和依赖，耗时较长。

## 参数说明

| 参数 | 值 | 说明 |
| --- | --- | --- |
| `BOARD` | `yjh-jm10-3588` | JM10 专用板卡配置 |
| `BRANCH` | `vendor` | 使用 Rockchip 6.1 vendor 补丁 |
| `BRANCH` | `legacy` | 使用 Rockchip 5.10 legacy 补丁 |
| `RELEASE` | `noble` | 示例使用 Ubuntu Noble；更换发行版前应确认补丁和驱动兼容性 |
| `BUILD_DESKTOP` | `no` | 无桌面系统，适合 NAS、路由和服务器用途 |
| `BUILD_MINIMAL` | `yes` | 尽量减少预装软件 |
| `KERNEL_CONFIGURE` | `no` | 不进入交互式内核配置 |
| `JM10_DSA_88E6390` | `yes`/`no` | 是否生成 Marvell MV88E6390X DSA 八口桥接配置 |

`JM10_DSA_88E6390` 默认是 `no`。普通单板构建无需额外设置。

## DSA 八口交换机模式

如果 JM10 使用板载 Marvell MV88E6390X 交换机，并希望将 `eth1` 到 `eth8` 加入 `br0`，使用以下命令构建：

```bash
./compile.sh \
  BOARD=yjh-jm10-3588 \
  BRANCH=vendor \
  RELEASE=noble \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes \
  KERNEL_CONFIGURE=no \
  JM10_DSA_88E6390=yes
```

DSA 模式当前只在 `vendor`/`legacy` 且 `BUILD_DESKTOP=no` 时生成运行时桥接配置。构建脚本会：

1. 将镜像文件名增加 `-dsa` 后缀。
2. 启用 `CONFIG_NET_VENDOR_MARVELL`、`CONFIG_NET_DSA`、`CONFIG_NET_DSA_MV88E6XXX`、`CONFIG_NET_DSA_MV88E6XXX_PTP` 和 `CONFIG_MVMDIO`。
3. 删除系统生成的 Netplan YAML，并写入 `/etc/netplan/10-dsa-MV88E6XXX-br0.yaml`。
4. 将 `eth1` 至 `eth8` 加入 `br0`，由 `br0` 通过 DHCP 获取地址。
5. 将 Netplan 渲染器设置为 `networkd`，并关闭交换机端口自身的 DHCP。

注意：当前板卡 hook 会在 `legacy`/`vendor` 构建中始终请求上述 DSA 内核配置；`JM10_DSA_88E6390` 主要控制 `-dsa` 镜像后缀和运行时 Netplan 桥接文件是否生成。

DSA 方案主要按 `vendor` 6.1 内核验证；`legacy` 5.10 的 DSA 组合未充分验证。建议先使用 vendor 构建测试。

首次启动后可以检查桥接状态：

```bash
ip link show br0
ip link show master br0
cat /etc/netplan/10-dsa-MV88E6XXX-br0.yaml
```

在 DSA 模式下，`eth1` 至 `eth8` 显示为 `ethN@end0` 是正常的：它们是挂在
GMAC 主接口 `end0` 下的 DSA 从属端口。启用 `JM10_DSA_88E6390=yes` 后，
上述 Netplan 文件应存在，并且 `ip link show br0` 应能看到桥；如果只有
`eth1` 至 `eth8` 而没有 `br0`，先确认构建命令确实传入了该参数，并检查：

```bash
test -f /etc/netplan/10-dsa-MV88E6XXX-br0.yaml
sudo netplan generate
```

生成的配置使用 DHCP。如果需要静态地址，应在目标板上修改该 Netplan 文件中的 `br0` 配置，然后执行：

```bash
sudo netplan apply
```

### 交换芯片网口 LED

JM10 的八个 RJ45 口由 Marvell MV88E6190/6390（Linux 中归入
`MV88E6390` family）内部 PHY 管理，LED 不是由 RK3588 的 GPIO 或 Netplan
驱动。Marvell 数据手册（88E6390/88E6190/88E6290，2018-01-23，2.4 节、
表 17/18）规定端口 1--8 的 LED 选择寄存器是每端口寄存器 `0x16` 的
Index 0；选择器 `0x2` 表示 LED0 为千兆 Link/Act、LED1 为 10/100
Link/Act。

原 6.1 `mv88e6xxx` 驱动没有初始化 6390 的 `0x16`，所以部分 JM10 板卡
会保留硬件 strap 的常亮选择。vendor 6.1 构建会额外应用
`kernel-rk35xx-vendor-003-mv88e6390-led.patch`，在交换机初始化时对端口
1--8 写入 `0x8022`（bit 15 为 update，低字节 `0x22` 为两个 LED 的
`0x2` 选择器）。这与端口转发、桥接配置无关；若升级后 LED 仍全亮，应
先确认运行的是带该补丁的 `vendor` 内核，再从交换机 MDIO 读取各端口
寄存器 `0x16`，预期选择器为 `0x2/0x2`。

## JM10 专用功能

### 内核和设备树

板卡配置会按 `BRANCH` 自动选择补丁目录：

- `legacy`：`userpatches/kernel/rockchip-5.10-yjh-jm10/`
- `vendor`：`userpatches/kernel/rockchip-6.1-yjh-jm10/`

JM10 不再在板卡 hook 中固定 vendor 内核提交；vendor 内核分支沿用
`config/sources/families/rockchip-rk3588.conf` 当前定义的最新版
`rk-6.1-rkr5.1`。loader 和 U-Boot 仍使用上文所述的冻结配置。

两个目录都包含 JM10 DTS 补丁以及针对 DSA、RGMII、Type-C/USB 的修正。补丁会把 `rk3588-yjh-jm10.dts` 注册到对应内核的设备树 Makefile。

### USB 调试套件（可选，`JM10_USB_DEBUG=yes`）

JM10 没有引出 TTL 调试串口，内核起不来时完全无输出。构建系统提供
一套**可选**的、全部走 MaskROM Type-C 口的调试设施，默认关闭，
构建时传 `JM10_USB_DEBUG=yes` 启用（仅 vendor 分支）：

```bash
./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor RELEASE=trixie \
  BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_CONFIGURE=no \
  JM10_DSA_88E6390=yes JM10_USB_DEBUG=yes
```

启用后追加应用两组补丁目录并调整内核配置：

- U-Boot `patch/u-boot/legacy/u-boot-radxa-rk35xx-yjh-jm10-3588-debug/`
  （崩溃转储 + 看门狗，见下文第 2 条）
- 内核 `userpatches/kernel/rockchip-6.1-yjh-jm10-debug/`
  （Type-C CDC 控制台）
- 内核配置：`CONFIG_USB_G_SERIAL=y`、
  `CONFIG_BOOTPARAM_RCU_STALL_PANIC=y`、`RCU_CPU_STALL_TIMEOUT=10`
- `armbianEnv.txt` 的 `extraargs` 追加 `console=ttyGS0,115200
  panic=10`；systemd 硬件看门狗 `RuntimeWatchdogSec=10`

**1. USB CDC-ACM 内核控制台**

`kernel-rk35xx-vendor-004-typec-cdc-console.patch` 把 MaskROM Type-C
对应的 `usbdrd_dwc3_0` 固定为 `peripheral` 模式。内核启动后
（gadget 初始化完成，约开机后几秒），把 Type-C 连到电脑即可看到
完整内核日志——printk 积压会在 gadget 连接时回放：

```bash
# 主机侧
dmesg -w &            # 或: cat /dev/ttyACM0
ls /dev/ttyACM0       # 设备枚举为 ttyACM*
```

局限：如果内核在 gadget 初始化之前就挂死（早期崩溃），该通道拿
不到日志，此时用第 2 条。

**2. U-Boot pstore/ramoops 崩溃转储**

U-Boot 补丁 `u-boot-rk35xx-legacy-002-crashlog-to-emmc.patch` 在进入
download 模式（开机或复位时**按住音量+（VOL+）**，或 Linux 里
`reboot loader`）时，把 RAM 中的 ramoops/pstore 区
（`0x110000..0x1f0000`，内核 console 日志与 U-Boot 自身日志都在
这里，内核 `rk3588-linux.dtsi` 的 `ramoops` 节点 + U-Boot
`CONFIG_PSTORE`）转储到 eMMC 4M–8M 空闲区（LBA 0x2000）：

```bash
# 进入 download 模式后，主机侧：
sudo rkdeveloptool rl 0x2000 0x700 jm10-crashlog.bin
strings jm10-crashlog.bin | less
```

注意区分设备状态：RKDevTool 里 **LOADER** = U-Boot 在跑（转储
有效）；**MASKROM** = ROM 在跑（转储没执行，按住的是 BOOT 键而非
VOL+）。ramoops 依赖 DDR 内容跨复位保留——出问题后用热复位，
不要断电重启；冷启动会丢日志。该 U-Boot 补丁同时设置
`CONFIG_PERSISTENT_RAM_ADDR=0x110000` 作为无 ATAG_PSTORE 时的
兜底，保证 U-Boot/SPL 自身日志一定落盘。

**「挂死转热复位」三保险**（调试套件启用时），保证挂死后
pstore 日志可恢复：

1. **U-Boot 看门狗预武装**（`u-boot-rk35xx-legacy-003-arm-watchdog.patch`）：
   `rk_board_late_init()` 在启动内核前开 DW 看门狗（WDT0@0xfeaf0000，
   24MHz，TORR=15 ≈ 89s）。内核挂死 → 89s 后**热复位** → DDR/pstore
   保留。内核 `DW_WATCHDOG=y` 起来后自动接管喂狗（`&wdt` 已使能），
   健康启动不会误咬。VOL+ 进 download 模式的路径不开狗（该路径不
   经过 `rk_board_late_init`）。fastboot/recovery 等长会话会被咬，
   用 MaskROM 刷机代替。
2. **RCU stall → panic**（`CONFIG_BOOTPARAM_RCU_STALL_PANIC=y` +
   `RCU_CPU_STALL_TIMEOUT=10`）：软死锁类挂死 10 秒后 panic →
   `panic=10` 热重启。
3. **`panic=10` + systemd 硬件看门狗 `RuntimeWatchdogSec=10`**。

**抓取流程（挂死后）**：等待 10–100 秒让看门狗/panic 热复位发生，
期间**按住 VOL+ 不放**——下次 U-Boot 启动即进 download 模式并自动
转储；然后 `rkdeveloptool rl 0x2000 0x700` 取回日志。

### PCIe / mSATA（板上未引出 PCIe 线路）

板上标注的扩展槽实际是 **mSATA（SATA 协议）**，由 `sata0` 驱动。
RK3588 除 `pcie2x1l0`（板载 AP6275P WiFi 使用）外，没有把任何其它
PCIe 控制器（`pcie3x4`/`pcie3x2`/`pcie2x1l1`/`pcie2x1l2`）引到可用
接口——曾尝试启用 `pcie3x4`，系统在总线枚举时挂死，随后确认该
x4 通道板上未布线。相关启用与调试补丁均已移除，本板不启用 PCIe。

### U-Boot 固定版本与启动修复

新基线的 `next-dev-v2024.10` U-Boot 在 JM10 上无法启动，而使用旧镜像中的 U-Boot 可以正常启动。JM10 当前固定使用 Radxa U-Boot 提交：

```text
22849bf1cf13c2f0a6f2741a51d4802793d2aecc
```

板卡 hook 会在构建配置的后期覆盖 RK3588 家族默认值，因此上游更新家族 U-Boot 分支不会改变 JM10 的 U-Boot。JM10 还使用独立的冻结补丁目录，只包含保证可启动的最小补丁集，不会继承公共目录后续新增的 U-Boot 补丁：

```text
patch/u-boot/legacy/u-boot-radxa-rk35xx-yjh-jm10-3588/
```

其中一个补丁关闭 `CONFIG_OPTEE_ALWAYS_USE_SECURITY_PARTITION`，另一个补丁增加 RK3566 的 Rockchip 镜像名称支持。`JM10_USB_DEBUG=yes` 时会追加 `-debug` 目录（崩溃转储 + 看门狗，见上文「USB 调试套件」）。不要把 `BOOTBRANCH` 改回家族默认值，也不要将 `BOOTPATCHDIR` 改为 `legacy/u-boot-radxa-rk35xx` 或追加 `v2024.10` 目录，否则可能再次生成无法启动的 U-Boot。

当前固定 U-Boot 的构建配置位于 [`config/boards/yjh-jm10-3588.csc`](config/boards/yjh-jm10-3588.csc)。

### 蓝牙和无线

构建镜像时会安装 JM10 所需的 `rk3588-bluetooth.service`，并将服务中的蓝牙串口调整为 `ttyS1`，同时安装 `rfkill`。首次启动后可检查：

```bash
systemctl status rk3588-bluetooth.service
rfkill list
```

### 音频名称

系统会写入 udev 规则，将 HDMI0 音频设备标记为 `HDMI0 Audio`，便于桌面或音频服务识别。

### 防止补丁被升级覆盖

板卡初始化逻辑会自动 hold 当前分支的内核、设备树和 U-Boot 包：

- legacy：`linux-image-legacy-rk35xx`、`linux-dtb-legacy-rk35xx`、`linux-u-boot-yjh-jm10-3588-legacy`
- vendor：`linux-image-vendor-rk35xx`、`linux-dtb-vendor-rk35xx`、`linux-u-boot-yjh-jm10-3588-vendor`

这是为了避免带有 JM10 定制 DTS 的镜像在系统升级后被官方包替换。确认新内核已验证后，可以在目标板上解除 hold：

```bash
sudo apt-mark unhold \
  linux-image-vendor-rk35xx \
  linux-dtb-vendor-rk35xx \
  linux-u-boot-yjh-jm10-3588-vendor
```

如果使用 legacy，将上述包名中的 `vendor` 替换为 `legacy`。

## 目录和修改规则

| 目录/文件 | 作用 |
| --- | --- |
| `config/boards/yjh-jm10-3588.csc` | 板卡主配置、构建分支选择、蓝牙、DSA 和升级锁定逻辑 |
| `userpatches/kernel/rockchip-5.10-yjh-jm10/` | 5.10 legacy 内核补丁 |
| `userpatches/kernel/rockchip-6.1-yjh-jm10/` | 6.1 vendor 内核补丁 |
| `patch/u-boot/legacy/u-boot-radxa-rk35xx-yjh-jm10-3588/` | JM10 冻结 U-Boot 补丁集 |
| `packages/bsp/rk3399/` | 复用的蓝牙工具和 systemd 服务模板 |
| `userpatches/customize-image.sh` | 通用镜像定制脚本，JM10 默认流程不依赖其中的旧版 OMV 函数 |

修改 DTS 时必须同时检查 5.10 和 6.1 两套补丁。通常应先修改两个 `001-add-yjh-jm10-dts.patch`，再同步修改两个 `002-fix-jm10-dsa...patch`，并分别在对应内核分支上验证补丁能否应用。

不要直接把 JM10 的 DTS 放到 `config/boards/` 中；板卡配置只负责选择补丁和声明 DTB，实际 DTS 内容由内核补丁提供。

## 相关提交

JM10 功能主要由以下本地提交形成：

- `da15deb33`：新增 JM10 板卡配置、DTS 和 legacy U-Boot 补丁。
- `c1fea00f8`：增加 MV88E6390X DSA、RGMII、Type-C/USB 相关 DTS 修正。
- `fdd6781a8`：增加内核包 hold、`rfkill`、DSA Netplan 桥接文件和 `-dsa` 镜像后缀。
- `49f26a39d`：将 JM10 U-Boot 固定到已验证可启动的提交 `22849bf1cf13c2f0a6f2741a51d4802793d2aecc`。
- `da10659b9`：冻结 JM10 的 U-Boot 补丁集，隔离后续公共 U-Boot 更新。

上游 Armbian 构建框架的更新会继续合并到本仓库，但应重点检查 `config/boards/yjh-jm10-3588.csc` 中的 hook 名称、内核补丁接口和包名是否仍与上游一致。
