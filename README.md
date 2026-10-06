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
| `PROXMOX` | `no` | 设为 `yes` 后在 Debian Trixie 上预装 Proxmox VE，保留 Armbian 内核并使用 ifupdown2 |

`JM10_DSA_88E6390` 默认是 `no`。普通单板构建无需额外设置。

另有一项**不需要任何参数、也不受 `KERNEL_CONFIGURE` 影响**的内核改动：内核虚拟
地址空间被固定在 39 位（`CONFIG_ARM64_VA_BITS=39`，`CONFIG_ARM64_VA_BITS_48` 为
not set）。原因和去掉的办法见下文
[39 位虚拟地址空间](#39-位虚拟地址空间android-容器内的游戏)。

## Proxmox VE 镜像

使用 `PROXMOX=yes` 将镜像构建为 Debian Trixie 上的 Proxmox VE 9 主机。该模式只支持 `amd64` 和 `arm64`，默认主机名为 `pve`（显式传入 `HOST=...` 时保留自定义值），会安装官方 no-subscription 仓库中的 PVE 用户空间与 ZFS DKMS，并保留 Armbian 内核。镜像文件名增加 `-proxmox` 后缀。版本与依赖约束遵循 [Armbian Proxmox 说明](https://docs.armbian.com/software/proxmox-ve/)。

```bash
./compile.sh \
  BOARD=yjh-jm10-3588 \
  BRANCH=vendor \
  RELEASE=trixie \
  BUILD_DESKTOP=no \
  BUILD_MINIMAL=yes \
  KERNEL_CONFIGURE=no \
  PROXMOX=yes
```

网络由 ifupdown2 管理，首次启动会通过 DHCP 配置 `vmbr0`；检测到 DSA 交换机端口时会将 DSA 从属端口加入该桥。Proxmox Web UI 地址为 `https://<主机IP>:8006`，使用 `root` 和系统 root 密码登录。ZFS DKMS 需要可用的 Armbian 内核 headers，因此不支持缺少 headers 的内核配置。

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
2. 在内核配置中强制内建（`=y`）Marvell 交换机驱动及其依赖链：
   `CONFIG_NET_DSA`、`CONFIG_NET_DSA_MV88E6XXX`、`CONFIG_NET_DSA_MV88E6XXX_PTP`、
   `CONFIG_PTP_1588_CLOCK`、`CONFIG_NET_VENDOR_MARVELL`、`CONFIG_MVMDIO`，
   以及为解开 Kconfig 依赖上限而必须一起内建的 `CONFIG_IPV6`、`CONFIG_BRIDGE`、
   `CONFIG_HSR`（见下）。
3. 删除系统生成的 Netplan YAML，并写入 `/etc/netplan/10-dsa-MV88E6XXX-br0.yaml`。
4. 将 `eth1` 至 `eth8` 加入 `br0`，由 `br0` 通过 DHCP 获取地址。
5. 将 Netplan 渲染器设置为 `networkd`，并关闭交换机端口自身的 DHCP。

注意：板卡 hook 会在 `legacy`/`vendor` 构建中始终请求上述内核配置（无论
`JM10_DSA_88E6390` 取值）；`JM10_DSA_88E6390` 只控制 `-dsa` 镜像后缀和运行时
Netplan 桥接文件是否生成。驱动本身必须始终在核里，否则交换机端口根本不会出现。

### 为什么 IPV6 / BRIDGE / HSR 也被强制内建

Kconfig 里这三个是 tristate 依赖，而 **tristate 依赖会把被依赖项的值"封顶"**：

```
BRIDGE            depends on IPV6 || IPV6=n      (net/bridge/Kconfig)
NET_DSA           depends on BRIDGE || BRIDGE=n
                  depends on HSR || HSR=n        (net/dsa/Kconfig)
NET_DSA_MV88E6XXX depends on NET_DSA             (drivers/net/dsa/mv88e6xxx/Kconfig)
```

`X || X=n` 这种写法只有 `X=y` 或 `X=n` 才成立，`X=m` 会让整个表达式取 `m`。所以
仓库自带配置里的 `IPV6=m` / `BRIDGE=m` / `HSR=m` 会把 `NET_DSA` 和
`NET_DSA_MV88E6XXX` 一路压成 `=m`，在 `.config` 里请求 `=y` 是无效的——实测
只请求 `NET_DSA=y` 得到的仍是 `CONFIG_NET_DSA=m`。四个选项必须一起动。

代价是 IPv6、网桥、STP、LLC 和 IP 隧道栈（`INET_TUNNEL`、`NET_IP_TUNNEL`、
`IPV6_SIT`、`MPTCP_IPV6`）也随之内建、不再可卸载（`Image` 略大）。顺带一提，
Armbian 内核核心 hook 本来就在请求 `CONFIG_BRIDGE=y`
（`lib/functions/compilation/armbian-kernel.sh` 的 `opts_y+=("BRIDGE")`），
只是被 `IPV6=m` 一直压成 `=m`。

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
ls /sys/module/mv88e6xxx                                   # 驱动在内核里（内建的也有这个目录）
grep -w mv88e6xxx "/lib/modules/$(uname -r)/modules.builtin"
dmesg | grep -i mv88e6xxx
test -f /etc/netplan/10-dsa-MV88E6XXX-br0.yaml
sudo netplan generate
```

驱动是内建的，所以不要用 `modinfo mv88e6xxx` 判断：内建驱动没有 `.ko`，
`modinfo` 会报 “Module not found”，即使驱动明明在核里。`/sys/module/` 下没有
`mv88e6xxx` 目录、`modules.builtin` 里也找不到，才说明内核根本没编出这个
驱动，与 Netplan 无关——那台机器刷的是没有 `CONFIG_NET_DSA_MV88E6XXX` 的镜像
（早期板卡 hook 在 `KERNEL_CONFIGURE=yes` 时会跳过这段内核配置），需要
重编内核并重刷，而不是在目标板上修网络配置。

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

### 39 位虚拟地址空间（Android 容器内的游戏）

本仓库的构建**无条件**把内核设成 `CONFIG_ARM64_VA_BITS=39`（相应地
`CONFIG_ARM64_VA_BITS_48` 为 not set）：不需要 `KERNEL_CONFIGURE`，`KERNEL_CONFIGURE=no`
也一样生效。

原因：部分 Android 游戏在 Docker 容器里一启动就闪退——它们要预留的地址区间和
48 位地址空间的布局撞上了，于是在自己的初始化代码里就挂掉。Android 手机本身就是
4K 页 + 39 位 VA，把容器摆成和手机相同的布局，这些游戏就能起来。**代价是实打实
的**：用户态地址空间从 128 TiB 降到 256 GiB，`mmap` 随机化位数上限从 33 降到
24，页表从 4 级降到 3 级。不跑 Android 容器就没必要背着它，见下面「不需要时怎么
去掉」。

实现在 `config/boards/yjh-jm10-3588.csc` 的
`custom_kernel_config__JM10-3588_va_bits_39()`，只往 `opts_y` 里加了一条
`ARM64_VA_BITS_39`。之所以一条就够，是因为 Armbian 内核核心在**每次 arm64 构建**
里都会强制 48 位：

```bash
# lib/functions/compilation/armbian-kernel.sh
function armbian_kernel_config__force_pa_va_48_bits_on_arm64() {
	if [[ "${ARCH}" == "arm64" ]]; then
		opts_y+=("ARM64_VA_BITS_48")
		opts_val["ARM64_PA_BITS"]="48"
	fi
}
```

这个核心 hook 属于 `armbian_kernel_config` 阶段，板卡 hook 属于它之后的
`custom_kernel_config` 阶段，两个阶段往**同一个** `opts_y` 数组里追加，所以核心的
`48` 先应用、板卡的 `39` 后应用。两者都进了 `.config` 之后，Kconfig 是按文件顺序
解析 choice 的，**最后一个 `=y` 的成员胜出**；而 `scripts/config` 对文件里还不存在
的符号是追加到文件末尾的，所以 `39` 排在 `48` 后面，赢。构建日志里 Kconfig 会留
一句

```
.config:2757:warning: override: ARM64_VA_BITS_39 changes choice state
```

这句 `override` 就是它承认自己按后一条改了 choice，看到它是正常的，不是错误。

由此有一条约束：**不要在 `config/kernel/linux-rk35xx-vendor.config` 里手写任何
`CONFIG_ARM64_VA_BITS*`**。现在没有，`make savedefconfig`（Armbian 会跑，并把结果
拷回这个文件）也不会写——39 正是这个 vendor 内核自己的默认值。但手工加上
`CONFIG_ARM64_VA_BITS_39=y` 会排在核心追加的 `48` **前面**，choice 就又解析回 48 了。
反过来 `CONFIG_ARM64_VA_BITS_48=y` 无害（上游 Armbian 的配置里就有这行），下一次
导出会把它去掉。

补一句背景：vendor 6.1 的 `arch/arm64/Kconfig` 里 4K 页的 choice 默认值是 39
（`default ARM64_VA_BITS_39 if ARM64_4K_PAGES`），和上游 mainline 的 48 不同。所以
这个改动本质上是「别让核心 hook 把它顶回 48」。

#### 不需要时怎么去掉

不跑 Android 容器的话改回去就行：

```bash
git revert <本提交>          # 或手动删掉 custom_kernel_config__JM10-3588_va_bits_39()
./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor RELEASE=trixie \
  BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no JM10_DSA_88E6390=yes
```

内核回到 Armbian 默认的 48 位 VA，其余（DSA、Proxmox、UEFI 等）都不受影响；因为
`.config` 变了，这一次会重编内核，之后照常命中缓存。刷机后在目标板上确认：

```bash
zcat /proc/config.gz | grep ARM64_VA_BITS   # 39 位期望：..._39=y、..._48 is not set
```

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

### 从 eMMC 引导外置盘（可选，`JM10_BOOT_EXTERNAL=yes`）

把完整系统放在外置 **USB2 盘 / mSATA(sata0) 盘**上，eMMC 只承担引导
（仅放 loader + U-Boot）。构建时传：

```bash
./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor RELEASE=trixie \
  BUILD_DESKTOP=no BUILD_MINIMAL=no KERNEL_CONFIGURE=no \
  JM10_DSA_88E6390=yes JM10_BOOT_EXTERNAL=yes
```

启用后：

- **U-Boot** 应用 `patch/u-boot/legacy/u-boot-radxa-rk35xx-yjh-jm10-3588-bootext/`
  的四个补丁（独立目录，与 `-debug`/USB 调试套件互不依赖）：
  使能 **SATA/SCSI**（`sata0`/`combphy0_ps`，即 mSATA）、**USB2 host**
  （host0/host1 的 EHCI+OHCI，VBUS 复用 gpio4 RK_PB0），并把
  `boot_targets` 调整为 **USB → SATA(SCSI) → SD → eMMC**（eMMC 最后）。
- **额外产物** `${version}.bootloader.img`（16 MiB **无分区表的裸
  loader 镜像**：`idbloader.img` @ 扇区 64 + `u-boot.itb` @ 扇区
  16384，与同版本完整镜像前部字节一致；BootROM/SPL 只读这两个固定
  偏移），随镜像自动压缩/搬进 `output/images/`。

使用：把 `.bootloader.img` 烧到 eMMC 前 16 MiB（RKDevTool「下载
镜像」或 `rkdeveloptool wl 0`；镜像不带 GPT，工具会按裸镜像从
LBA 0 写入），再把完整 Armbian 镜像烧到外置 USB2 盘或 mSATA，插盘
开机即可由 eMMC 引导外置系统。实测验证：完整镜像与 bootloader
镜像均能引导 USB 外置盘启动。

注意：**不要**给 bootloader 镜像加分区表——带 GPT 时烧写工具会按
分区语义重排写入（RKDevTool 对非标准 GPT 布局的裸镜像会失败），
之前版本因此无法启动。

限制与注意：

1. 外置 USB 走 **USB2/A 口**（EHCI/OHCI）。USB3/dwc3-host 不使能，
   以保留 Type-C 口的 rockusb 刷机/CDC 调试 gadget 角色。
2. 外置盘是完整镜像时，其 `/boot/armbianEnv.txt` 的 root 默认指向
   `mmcblk0p1`（针对 eMMC 整盘安装）；改为指向外置盘 root 分区，
   例如 `rootdev=/dev/sda1`（USB）或对应 SATA 节点，否则内核挂载错盘。
3. USB2 host 引导已实测通过（完整镜像和 bootloader 镜像均能从 USB
   外置盘启动）；mSATA/SCSI 引导路径尚待实测。观察引导顺序可用
   `JM10_USB_DEBUG=yes` 的 ttyGS0 控制台看 `Scanning usb 0:1` →
   `scsi 0` → `mmc1` → `mmc0`。

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
