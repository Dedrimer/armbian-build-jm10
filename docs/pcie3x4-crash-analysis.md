# JM10 PCIe 3.0 x4 插槽崩溃分析

- 日期：2026-09-05
- 崩溃日志存档：`output/crashlog-pcie3x4-20260905.txt`
- 触发镜像：`Armbian-unofficial_26.11.0-trunk_Yjh-jm10-3588_trixie_vendor_6.1.115-dsa.img`（含 005 补丁，构建 UUID 8309ba0a）
- 参考文档：《Rockchip PCIe 开发指南》V6.26（2025-05-22）

## 背景

JM10 的 x4 插槽对应 `&pcie3x4`（`fe150000`，PCIe Gen3 x4），vendor
DTS 从未启用它。本次尝试用板级 DTS 补丁启用（005 补丁），配置完全
照抄指南 2.5.1 节 RK3588 EVB1 参考设计（聚合模式 + PERST#
`gpio4 RK_PB6` + `vpcie3v3` + `perst-inactive-ms 500`），并核对了
gpio4 B4/B5/B6（PERST/WAKE/CLKREQ m1 复用）在 JM10 DTS 中无其它占用。

## 现象

刷入后整机反复 panic 循环（约 30 秒一轮），ttyGS0 USB CDC 控制台
不出现（内核死在 gadget 初始化之前）。通过 USB 调试套件
（`JM10_USB_DEBUG=yes`）的崩溃转储链抓到完整日志。

## 日志时间线

```
2.257s  dw-pcie fe150000: invalid resource → Failed to initialize host (-22)
        （首次同步 probe 失败后由 kthread 重试——正常流程）
2.257s  fe150000/fe170000 regulator vcc3v3_pcie30 就绪
2.258s  mpp_service probe start
2.816s  fe170000 (pcie2x1l0, WiFi): PCIe Link up, LTSSM 0x30011   ← 成功
2.258~12.25s  fe150000 的 rk-pcie kthread 静默挂死（9.4 秒）
12.25s  RCU stall 检测（RCU_CPU_STALL_TIMEOUT=10）
13.25s  Kernel panic - not syncing: RCU Stall
15.66s  Rebooting in 10 seconds（panic=10）
复位    → 下一轮循环
```

## 死因（来自 panic 栈）

软死锁，两个核互相卡死：

- **CPU2**（`rk-pcie` kthread，`CONFIG_PCIE_RK_THREADED_INIT=y`，
  fe150000 的 probe 线程）：
  ```
  dw_pcie_host_init → pci_host_probe → pci_scan_root_bus_bridge
  → pci_register_host_bridge → device_add → kernfs（持锁）
  → 枚举总线 → config 空间 readl —— 永不返回
  ```
- **CPU1/CPU7** 分别停在 `dw_pcie_read+0x20` 和裸 `readl`——对
  fe150000 的 DBI/config 寄存器读挂起，AMBA 总线层无超时。
- **CPU5**（pid 1，`mpp_service_probe → device_create → sysfs`）
  在 kernfs 自旋锁上自旋等待 CPU2 释放 → RCU stall → panic。

**config 空间读永不返回 = 控制器时钟域未真正就绪。** PHY 驱动侧
没有 `lock failed`（`SRAM_INIT_DONE` 检查通过），说明 PHY SRAM 初始化
完成，但这与「远端 100MHz 参考时钟满足规范」不是一回事。

## 反证（软件配置无误）

同一 DTS、同一驱动的 `fe170000`（pcie2x1l0，WiFi 用，走 combphy）
完整走通 probe 并 `Link up, LTSSM 0x30011`（指南 12.7 的成功判据）。
vpcie3v3 regulator 使能正常。GPIO 无冲突。`reset-gpios` 获取成功。

## 结论

**软件侧已无可收敛空间**。fe150000 在枚举阶段 config 读挂死的
最可能原因是 **x4 插槽 100MHz 参考时钟路径没有真正工作**——PHY
SRAM done 不代表 refclk 幅度/质量达标；时钟异常时控制器时钟域
半就绪，寄存器访问直接挂起。这与指南 13.3「PCIe3.0控制器初始化
设备系统异常」（RCU stall + rk-pcie 挂死）描述的现象一致，该节
也是 RK 官方对同类问题的记载。

## 下一步（硬件排查，按指南 13.3 优先级）

1. **x4 插槽 100MHz 参考晶振**：确认是否焊接、供电是否正常、
   示波器测输出幅度（NAS 板最常见缺失项）
2. **PCIE30_AVDD_0V75 / 1V8 实测电压**（DTS 的 always-on regulator
   只管软件侧使能，板上实际电压需万用表量）
3. **PERST# 走线确认**：量 GPIO4_B6 在 probe 窗口内是否有
   500ms 拉低再拉高的翻转（确认 PERST# 确实接在此脚）
4. （可选）示波器看 LTSSM 训练期间的差分线活动

## 重试模板

硬件排查完成后，把下面节点加回 `rk3588-yjh-jm10.dts` 即可重试
（005 补丁的完整内容）：

```dts
&pcie3x4 {
	reset-gpios = <&gpio4 RK_PB6 GPIO_ACTIVE_HIGH>;   /* pcie30x4_perstn_m1 */
	vpcie3v3-supply = <&vcc3v3_pcie30>;
	rockchip,perst-inactive-ms = <500>;
	status = "okay";
};
```

建议重试时带 `JM10_USB_DEBUG=yes`：`RK_PCIE_DBG`（006 补丁）会在
链路训练时打印 LTSSM 与 fifo_status（判读表见指南附录 14.1），
ttyGS0 控制台与崩溃转储链保证任何挂死都有日志。若怀疑时钟裕量
不足，可先试 `max-link-speed = <1>`（Gen1 对时钟质量要求低一档）。

## 本次事故的附带收获

调试链路全程验证有效，值得记录：

- 挂死 → RCU stall panic（10s）→ `panic=10` 热复位（保留 DDR）
- 热复位后按 VOL+ → U-Boot download 模式 → `do_board_download()`
  自动转储 pstore/ramoops 区到 eMMC LBA 0x2000
- 主机 `rkdeveloptool rl 0x2000 0x700` 取回 → 完整 kernel+U-Boot 日志

任何后续板级调试（不仅是 PCIe）都可复用该流程。
