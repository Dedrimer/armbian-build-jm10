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

生成的配置使用 DHCP。如果需要静态地址，应在目标板上修改该 Netplan 文件中的 `br0` 配置，然后执行：

```bash
sudo netplan apply
```

## JM10 专用功能

### 内核和设备树

板卡配置会按 `BRANCH` 自动选择补丁目录：

- `legacy`：`userpatches/kernel/rockchip-5.10-yjh-jm10/`
- `vendor`：`userpatches/kernel/rockchip-6.1-yjh-jm10/`

两个目录都包含 JM10 DTS 补丁以及针对 DSA、RGMII、Type-C/USB 的修正。补丁会把 `rk3588-yjh-jm10.dts` 注册到对应内核的设备树 Makefile。

legacy U-Boot 的额外配置位于：

```text
patch/u-boot/legacy/u-boot-radxa-rk35xx/board_yjh-jm10-3588/
```

该补丁关闭 `CONFIG_OPTEE_ALWAYS_USE_SECURITY_PARTITION`，不要随意删除，否则可能影响 JM10 的 legacy 启动流程。

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
| `patch/u-boot/legacy/u-boot-radxa-rk35xx/board_yjh-jm10-3588/` | legacy U-Boot 补丁 |
| `packages/bsp/rk3399/` | 复用的蓝牙工具和 systemd 服务模板 |
| `userpatches/customize-image.sh` | 通用镜像定制脚本，JM10 默认流程不依赖其中的旧版 OMV 函数 |

修改 DTS 时必须同时检查 5.10 和 6.1 两套补丁。通常应先修改两个 `001-add-yjh-jm10-dts.patch`，再同步修改两个 `002-fix-jm10-dsa...patch`，并分别在对应内核分支上验证补丁能否应用。

不要直接把 JM10 的 DTS 放到 `config/boards/` 中；板卡配置只负责选择补丁和声明 DTB，实际 DTS 内容由内核补丁提供。

## 相关提交

JM10 功能主要由以下本地提交形成：

- `da15deb33`：新增 JM10 板卡配置、DTS 和 legacy U-Boot 补丁。
- `c1fea00f8`：增加 MV88E6390X DSA、RGMII、Type-C/USB 相关 DTS 修正。
- `fdd6781a8`：增加内核包 hold、`rfkill`、DSA Netplan 桥接文件和 `-dsa` 镜像后缀。

上游 Armbian 构建框架的更新会继续合并到本仓库，但应重点检查 `config/boards/yjh-jm10-3588.csc` 中的 hook 名称、内核补丁接口和包名是否仍与上游一致。
