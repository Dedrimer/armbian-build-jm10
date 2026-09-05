# Yijiahe JM10-3588 Rockchip RK3588 Octa core 4GB-32GB eMMC GBE HDMI PCIe SATA USB3 WiFi 4G 5G
BOARD_NAME="Yijiahe JM10-3588"
BOARDFAMILY="rockchip-rk3588"
BOOT_SOC="rk3588"
BOARD_MAINTAINER="r-mt"
KERNEL_TARGET="legacy,vendor"
BOOTCONFIG="rk3588_defconfig"
BOOT_FDT_FILE="rockchip/rk3588-yjh-jm10.dtb"
BOOT_LOGO="desktop"
FULL_DESKTOP="no"
#硬改dsa交换机 设置 JM10_DSA_88E6390="yes" 内核版本这里使用vendor 6.1x, legacy 5.10内核未测试
#./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no RELEASE=noble JM10_DSA_88E6390=yes
# Keep the board default, but let a command-line parameter override it. The
# Armbian CLI parameters are applied before this board file is sourced.
declare -g JM10_DSA_88E6390="${JM10_DSA_88E6390:-no}"
# Optional USB debug kit (the board has no TTL UART). When "yes":
#   - U-Boot: crashlog-to-eMMC dump + pre-kernel watchdog (patches 002/003)
#   - kernel: Type-C CDC-ACM console (ttyGS0, patch 004)
#   - kernel config: g_serial, RCU-stall-panic; extraargs: console=ttyGS0, panic=10
# Build example:
# ./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor BUILD_MINIMAL=no RELEASE=trixie \
#               JM10_DSA_88E6390=yes JM10_USB_DEBUG=yes
declare -g JM10_USB_DEBUG="${JM10_USB_DEBUG:-no}"
# Boot-from-external mode (eMMC only carries the bootloader; the OS lives on
# an external USB2 / mSATA disk). When "yes":
#   - U-Boot: enable USB host (EHCI/OHCI) + SATA/SCSI, boot order USB->SATA->SD->eMMC
#   - output an extra dd-able ${version}.bootloader.img (16 MiB, idbloader+u-boot.itb)
# Build example:
# ./compile.sh BOARD=yjh-jm10-3588 BRANCH=vendor BUILD_MINIMAL=no RELEASE=trixie \
#               JM10_DSA_88E6390=yes JM10_BOOT_EXTERNAL=yes JM10_USB_DEBUG=yes
declare -g JM10_BOOT_EXTERNAL="${JM10_BOOT_EXTERNAL:-no}"
IMAGE_PARTITION_TABLE="gpt"
# SRC_EXTLINUX="yes"
# SRC_CMDLINE="rootwait earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 irqchip.gicv3_pseudo_nmi=0 rootfstype=ext4"

function post_family_config__yjh_jm10_3588_pin_uboot() {
	display_alert "$BOARD" "Pinning verified U-Boot commit for $BOARD" "info"

	# The JM10 boots with this Radxa U-Boot revision. Use only the frozen
	# 2024.03 patch set; do not inherit newer family U-Boot patches.
	declare -g BOOTSOURCE="https://github.com/radxa/u-boot.git"
	declare -g BOOTBRANCH="commit:22849bf1cf13c2f0a6f2741a51d4802793d2aecc"
	declare -g BOOTPATCHDIR="legacy/u-boot-radxa-rk35xx-yjh-jm10-3588"

	# Optional USB debug kit (JM10_USB_DEBUG=yes): crashlog dump to eMMC and
	# pre-kernel watchdog live in a separate patch dir so normal builds stay
	# minimal. See the README "通过 MaskROM Type-C 口调试" section.
	if [[ "${JM10_USB_DEBUG}" == "yes" ]]; then
		display_alert "$BOARD" "USB debug kit enabled: U-Boot crashlog dump + watchdog" "info"
		BOOTPATCHDIR="${BOOTPATCHDIR} legacy/u-boot-radxa-rk35xx-yjh-jm10-3588-debug"
	fi

	# Boot-from-external mode (JM10_BOOT_EXTERNAL=yes): USB host + SATA/SCSI
	# enablement and the USB->SATA->SD->eMMC boot-order patches live in a
	# separate dir, independently gated from -debug.
	if [[ "${JM10_BOOT_EXTERNAL}" == "yes" ]]; then
		display_alert "$BOARD" "Boot-from-external enabled: U-Boot USB/SATA + boot order" "info"
		BOOTPATCHDIR="${BOOTPATCHDIR} legacy/u-boot-radxa-rk35xx-yjh-jm10-3588-bootext"
	fi
}

function post_family_config__nas-lite_kernel() {
	display_alert "$BOARD" "JM10 kernel patch directory" "info"
	case ${BRANCH} in
		legacy)
			KERNELPATCHDIR="rockchip-5.10-yjh-jm10"
			;;
		vendor)
			KERNELPATCHDIR="rockchip-6.1-yjh-jm10"
			;;
	esac

	# Optional USB debug kit (JM10_USB_DEBUG=yes, vendor branch only):
	# Type-C CDC-ACM console (ttyGS0) patch.
	if [[ "${JM10_USB_DEBUG}" == "yes" ]] && [[ "${BRANCH}" == "vendor" ]]; then
		display_alert "$BOARD" "USB debug kit enabled: kernel ttyGS0 console patches" "info"
		KERNELPATCHDIR="${KERNELPATCHDIR} rockchip-6.1-yjh-jm10-debug"
	fi
}

function post_family_tweaks_bsp__JM10-3588() {
	display_alert "$BOARD" "Installing rk3588-bluetooth.service" "info"

	# Bluetooth on this board is handled by a Broadcom (AP6275PR3) chip and requires
	# a custom brcm_patchram_plus binary, plus a systemd service to run it at boot time
	install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
	cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/rk3588-bluetooth.service

	# Reuse the service file, ttyS0 -> ttyS6; BCM4345C5.hcd -> BCM4362A2.hcd
	sed -i 's/ttyS0/ttyS1/g' $destination/lib/systemd/system/rk3588-bluetooth.service
	sed -i 's/BCM4345C5.hcd/BCM4362A2.hcd/g' $destination/lib/systemd/system/rk3588-bluetooth.service
	return 0
}

function post_family_tweaks__JM10-3588_naming_audios() {
	display_alert "$BOARD" "Renaming JM10-3588 audios" "info"
	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	return 0
}

function extension_prepare_config__dsa() {
	if [[ ${JM10_DSA_88E6390} = "yes" ]] && [[ ${BRANCH} = "vendor" || ${BRANCH} = "legacy" ]] && [[ ${BUILD_DESKTOP} = "no" ]]; then
		display_alert "jm10-3588" "Only for Jm10 Hard Change Enabling MV88E6XXX Img Name -dsa" "info"
		EXTRA_IMAGE_SUFFIXES+=("-dsa")
	fi
}

function custom_kernel_config__JM10-3588_MV88E6XXX() {
	#if [[ ${JM10_DSA_88E6390} = "yes" ]] && [[ ${BRANCH} = "vendor" || ${BRANCH} = "legacy" ]]; then
		display_alert "jm10-3588" "Only for Jm10 Hard Change Enabling MV88E6XXX HASH" "info"
		kernel_config_modifying_hashes+=(
			"CONFIG_NET_VENDOR_MARVELL=y"
			"CONFIG_NET_DSA=m"
			"CONFIG_NET_DSA_MV88E6XXX=m"
			"CONFIG_NET_DSA_MV88E6XXX_PTP=y"
			"CONFIG_MVMDIO=y"
		)

		if [[ -f .config ]] && [[ "${KERNEL_CONFIGURE:-yes}" != "yes" ]]; then
			display_alert "jm10-3588" "Only for Jm10 Hard Change Enabling dsa MV88E6XXX" "info"
			kernel_config_set_y CONFIG_NET_VENDOR_MARVELL
			kernel_config_set_m CONFIG_NET_DSA
			kernel_config_set_m CONFIG_NET_DSA_MV88E6XXX
			kernel_config_set_y CONFIG_NET_DSA_MV88E6XXX_PTP
			kernel_config_set_y CONFIG_MVMDIO
			run_kernel_make olddefconfig
		fi
	#fi
}

# USB debug kit (JM10_USB_DEBUG=yes, vendor branch): g_serial built-in so the
# MaskROM Type-C port becomes a CDC-ACM serial console (ttyGS0), plus
# RCU-stall-panic so kernel hangs convert into warm-reboot panics that the
# U-Boot crashlog dump can capture. Requires the -debug kernel patch dir.
function custom_kernel_config__JM10-3588_usb_serial_console() {
	if [[ "${JM10_USB_DEBUG}" != "yes" ]] || [[ ${BRANCH} != "vendor" ]]; then
		return 0
	fi

	display_alert "jm10-3588" "Enabling USB gadget serial console (ttyGS0)" "info"
	kernel_config_modifying_hashes+=(
		"CONFIG_USB_G_SERIAL=y"
		# Convert kernel hangs into warm-reboot panics so the pstore/ramoops
		# crash log survives (warm reset keeps DDR; a hang keeps nobody alive
		# to log). The PCIe3.0 probe hang shows as an RCU stall (Rockchip PCIe
		# guide 13.3) - panic on it, then panic=10 in extraargs reboots warm.
		"CONFIG_BOOTPARAM_RCU_STALL_PANIC=y"
		"CONFIG_RCU_CPU_STALL_TIMEOUT=10"
	)

	if [[ -f .config ]] && [[ "${KERNEL_CONFIGURE:-yes}" != "yes" ]]; then
		kernel_config_set_y CONFIG_USB_G_SERIAL
		kernel_config_set_y CONFIG_BOOTPARAM_RCU_STALL_PANIC
		kernel_config_set_val CONFIG_RCU_CPU_STALL_TIMEOUT 10
		run_kernel_make olddefconfig
	fi
}


function post_family_tweaks__JM10-3588_ttygs_console() {
	# USB debug kit only. Kernel console on the MaskROM Type-C via g_serial
	# (CDC-ACM, /dev/ttyACM0 on the host), plus warm-reset insurance
	# (panic=10 auto-reboot, systemd hardware watchdog) so the
	# pstore/ramoops crash log survives a hang. Vendor branch only (the DTS
	# patch that puts usbdrd_dwc3_0 in peripheral mode is vendor-only).
	if [[ "${JM10_USB_DEBUG}" != "yes" ]] || [[ ${BRANCH} != "vendor" ]]; then
		return 0
	fi

	if [[ -f "${SDCARD}/boot/armbianEnv.txt" ]]; then
		display_alert "jm10-3588" "Adding console=ttyGS0 + panic=10 to extraargs" "info"
		sed -i 's/^extraargs=/extraargs=console=ttyGS0,115200 panic=10 /' "${SDCARD}/boot/armbianEnv.txt"
	fi

	# panic=10 auto-reboots (warm) on kernel panic; the systemd hardware
	# watchdog reboots (warm) if userspace hangs. Warm resets keep DDR (and
	# the pstore buffer at 0x110000) alive; a power cycle does not.
	if [[ -f "${SDCARD}/etc/systemd/system.conf" ]]; then
		display_alert "jm10-3588" "Enabling systemd hardware watchdog (RuntimeWatchdogSec=10)" "info"
		sed -i 's/^#\?RuntimeWatchdogSec=.*/RuntimeWatchdogSec=10/' "${SDCARD}/etc/systemd/system.conf"
		grep -q "^RuntimeWatchdogSec=" "${SDCARD}/etc/systemd/system.conf" ||
			echo "RuntimeWatchdogSec=10" >> "${SDCARD}/etc/systemd/system.conf"
	fi

	return 0
}

function post_family_tweaks__JM10-3588_enable_services() {
	display_alert "fix armbian upgrade; hold kernel and dtb"
	if [[ ${BRANCH} = "legacy" ]] ; then
		display_alert "$BOARD" "Enabling JM10-3588 upgrade lock dtb adn kernel" "info"
		chroot_sdcard apt-mark hold linux-image-legacy-rk35xx
		chroot_sdcard apt-mark hold linux-dtb-legacy-rk35xx
		chroot_sdcard apt-mark hold linux-u-boot-yjh-jm10-3588-legacy
	else
		display_alert "$BOARD" "Enabling JM10-3588 upgrade lock dtb adn kernel" "info"
		chroot_sdcard apt-mark hold linux-image-vendor-rk35xx
		chroot_sdcard apt-mark hold linux-dtb-vendor-rk35xx
		chroot_sdcard apt-mark hold linux-u-boot-yjh-jm10-3588-vendor
	fi

	display_alert "$BOARD" "Enabling rk3588-bluetooth.service" "info"
	chroot_sdcard_apt_get_install rfkill
	chroot_sdcard systemctl enable rk3588-bluetooth.service

	if [[ ${JM10_DSA_88E6390} = "yes" ]] && [[ ${BRANCH} = "vendor" || ${BRANCH} = "legacy" ]] && [[ ${BUILD_DESKTOP} = "no" ]]; then
		#Only for Jm10 Hard Change. del /etc/netplan/10-dhcp-all-interfaces.yaml and add 10-dsa-MV88E6XXX-br0.yaml
		#桌面配置	网络使用NetworkManager,自行图形化配置网桥,暂不用10-dsa-MV88E6XXX-br0.yaml配置网桥
		display_alert "$BOARD" "Only for Jm10 Hard Change del 10-dhcp-all-interfaces.yaml and add 10-dsa-MV88E6XXX-br0.yaml" "info"
		rm -rf ${SDCARD}/etc/netplan/*.yaml
		cat <<- EOF > "${SDCARD}/etc/netplan/10-dsa-MV88E6XXX-br0.yaml"
# Let NetworkManager manage all devices on this system
network:
  version: 2
  renderer: networkd
  ethernets:
    eth1:
      dhcp4: no
      dhcp6: no
    eth2:
      dhcp4: no
      dhcp6: no
    eth3:
      dhcp4: no
      dhcp6: no
    eth4:
      dhcp4: no
      dhcp6: no
    eth5:
      dhcp4: no
      dhcp6: no
    eth6:
      dhcp4: no
      dhcp6: no
    eth7:
      dhcp4: no
      dhcp6: no 
    eth8:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces:
        - eth1
        - eth2
        - eth3
        - eth4
        - eth5
        - eth6
        - eth7
        - eth8
      dhcp4: yes
      dhcp6: yes
      #addresses:
      #  - 192.168.3.166/24
      #routes:
      #  - to: default
      #    via: 192.168.3.1
      #nameservers:
      #  addresses: [192.168.3.1, 8.8.8.8]
      parameters:
        stp: false
EOF
	chmod 600 "${SDCARD}/etc/netplan/10-dsa-MV88E6XXX-br0.yaml"
	fi

	return 0
}

# JM10 boot-from-external (JM10_BOOT_EXTERNAL=yes): emit a 16 MiB dd-able
# loader image next to the full image: idbloader.img @ sector 64 and
# u-boot.itb @ sector 16384, byte-identical to the first 16 MiB of the full
# image (verified bootable by the full image itself). No partition table:
# the BootROM and SPL only read the two fixed offsets, and a GPT here only
# confuses tools (RKDevTool "download image" writes per-GPT-partition, so a
# bootloader GPT makes it re-lay the eMMC instead of a raw LBA write).
# dd/flash it to the front of the eMMC; keep the OS on an external
# USB2/mSATA disk.
function post_build_image__yjh_jm10_3588_bootloader_image() {
	[[ "${JM10_BOOT_EXTERNAL}" == "yes" ]] || return 0
	[[ -n "${FINAL_IMAGE_FILE:-}" ]] || return 0

	local uboot_deb="${DEB_STORAGE}/${image_artifacts_debs_reversioned["uboot"]}"
	[[ -f "${uboot_deb}" ]] || exit_with_error "U-Boot deb missing for bootloader image: ${uboot_deb}"

	local extract_dir uboot_lib out
	extract_dir="$(mktemp -d)"
	run_host_command_logged dpkg -x "${uboot_deb}" "${extract_dir}"
	uboot_lib="$(find "${extract_dir}/usr/lib" -maxdepth 1 -type d -name 'linux-u-boot-*' | head -1)"
	[[ -n "${uboot_lib}" && -f "${uboot_lib}/idbloader.img" && -f "${uboot_lib}/u-boot.itb" ]] \
		|| exit_with_error "idbloader.img/u-boot.itb missing in ${uboot_deb}"

	# 16 MiB sparse zero file, then the two blobs at the BootROM's fixed
	# offsets - exactly the full image's leading layout.
	out="${DESTIMG}/${version}.bootloader.img"
	run_host_command_logged dd if=/dev/zero of="${out}" bs=1M count=0 seek=16
	run_host_command_logged dd if="${uboot_lib}/idbloader.img" of="${out}" seek=64 conv=notrunc
	run_host_command_logged dd if="${uboot_lib}/u-boot.itb" of="${out}" seek=16384 conv=notrunc
	rm -rf "${extract_dir}"

	display_alert "$BOARD" "external-boot loader image -> ${out##*/}" "info"
	return 0
}
