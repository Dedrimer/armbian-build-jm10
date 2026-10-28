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

# Marvell MV88E6390X DSA switch support for the hard-modified JM10: eth1..eth8
# are switch ports hanging off the GMAC in DSA mode (see the README).
#
# The options are *declared*, not written: opts_y/opts_m/opts_val are applied by
# armbian_kernel_config_apply_opts_from_arrays(), which runs the scripts/config
# edits whenever a .config is in place -- KERNEL_CONFIGURE=yes included, where
# menuconfig merely opens on top of the result -- and only feeds
# kernel_config_modifying_hashes in the artifact-version phase, which has no
# tree. Writing the .config by hand here, behind a `KERNEL_CONFIGURE != yes`
# guard, is what used to make every KERNEL_CONFIGURE=yes build ship a kernel
# with `# CONFIG_NET_DSA_MV88E6XXX is not set` and no mv88e6xxx.ko.
#
# Requested on every legacy/vendor build, not only when JM10_DSA_88E6390=yes
# picks the -dsa image suffix and writes the Netplan bridge: the driver has to
# be in the kernel either way, and the Kconfig below is the only thing that
# decides whether it is.
#
# Built-in (=y), not =m -- and that reaches much further than the driver:
#
#   BRIDGE            depends on IPV6 || IPV6=n    (net/bridge/Kconfig)
#   NET_DSA           depends on BRIDGE || BRIDGE=n
#                     depends on HSR || HSR=n      (net/dsa/Kconfig)
#   NET_DSA_MV88E6XXX depends on NET_DSA           (drivers/net/dsa/mv88e6xxx/Kconfig)
#
# A tristate dependency *caps* what it guards, so with the shipped config's
# IPV6=m / BRIDGE=m / HSR=m the chain silently resolves to =m whatever is asked
# for here: `X || X=n` is satisfied by X=y or X=n, never by X=m. All four move
# together or mv88e6xxx stays a module. The pull-in is the price of a built-in
# switch driver: IPV6, BRIDGE, STP, LLC and the IP tunnel stack become built-in
# too. BRIDGE=y is in fact what Armbian core already asks for in opts_y -- with
# the shipped IPV6=m that request is being capped to =m today as well.
#
# None of these may appear in opts_m: opts_m is applied after opts_y, so the
# module value would win. Nothing else in the tree sets them; the only other
# mention is the tracked defconfig, which this overrides.
function custom_kernel_config__JM10-3588_MV88E6XXX() {
	display_alert "jm10-3588" "Forcing built-in Marvell MV88E6XXX DSA support" "info"

	# shellcheck disable=SC2034 # read by armbian_kernel_config_apply_opts_from_arrays
	opts_y+=(
		"IPV6"                  # uncaps BRIDGE
		"BRIDGE"                # uncaps NET_DSA, and needed for br0 anyway
		"HSR"                   # uncaps NET_DSA the other way; unused here otherwise
		"NET_DSA"               # DSA core; selects the DSA/EDSA taggers
		"NET_DSA_MV88E6XXX"     # the switch driver
		"NET_DSA_MV88E6XXX_PTP" # bool; needs PTP_1588_CLOCK=y ...
		"PTP_1588_CLOCK"        # ... so pin that dependency too
		"NET_VENDOR_MARVELL"    # menu gate for MVMDIO below
		"MVMDIO"                # Marvell MDIO bus driver; belt and braces, the
		                        # switch is on the GMAC's own MDIO (&mdio0 in the DTS)
	)
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

	# Declared rather than written, for the same reason as the MV88E6XXX hook
	# above: the `KERNEL_CONFIGURE != yes` guard this used to carry meant a
	# KERNEL_CONFIGURE=yes build got none of it, so the debug kit's console
	# never came up.
	# shellcheck disable=SC2034 # read by armbian_kernel_config_apply_opts_from_arrays
	opts_y+=(
		"USB_G_SERIAL"
		# Convert kernel hangs into warm-reboot panics so the pstore/ramoops
		# crash log survives (warm reset keeps DDR; a hang keeps nobody alive
		# to log). The PCIe3.0 probe hang shows as an RCU stall (Rockchip PCIe
		# guide 13.3) - panic on it, then panic=10 in extraargs reboots warm.
		"BOOTPARAM_RCU_STALL_PANIC"
	)
	# shellcheck disable=SC2034
	opts_val["RCU_CPU_STALL_TIMEOUT"]="10"
}

# 39-bit virtual address space instead of 48-bit, to stop some Android games
# from crashing on startup inside a Docker container: they reserve address
# ranges that collide with where a 48-bit layout puts things and die in their
# own initialiser. Android phones run 4K pages with a 39-bit VA -- which is
# also this vendor kernel's own default, unlike mainline's 48 -- so handing the
# container the same layout as the phone is what makes them start. The cost is
# real: user space gets 256 GiB instead of 128 TiB, mmap randomisation drops
# from 33 bits to 24, and the page tables go from 4 levels to 3. If you do not
# run Android containers, `git revert` this commit and rebuild.
#
# The mechanism is not the obvious one, so: Armbian core asks for 48-bit VA on
# *every* arm64 build -- armbian_kernel_config__force_pa_va_48_bits_on_arm64()
# in lib/functions/compilation/armbian-kernel.sh adds ARM64_VA_BITS_48 to
# opts_y. That runs in the `armbian_kernel_config` phase, before the
# `custom_kernel_config` phase this file's hooks live in, and both phases append
# to the same opts_y array, so core's entry is applied first and this one
# second. Both symbols then exist in .config, and Kconfig resolves a choice to
# the last member that says =y in file order -- which is ours, because
# scripts/config appends a symbol it has not seen yet to the end of the file.
#
# So the tracked config must not declare a VA_BITS symbol itself. It does not
# today, and `make savedefconfig` -- which Armbian runs and copies back over
# config/kernel/linux-rk35xx-vendor.config -- keeps omitting ARM64_VA_BITS_39
# because it is this kernel's default. A hand-added CONFIG_ARM64_VA_BITS_39=y
# would break it by sitting *before* the 48 that core appends; an explicit
# CONFIG_ARM64_VA_BITS_48=y is harmless and the next export strips it.
function custom_kernel_config__JM10-3588_va_bits_39() {
	display_alert "jm10-3588" "Forcing a 39-bit ARM64 virtual address space" "info"

	# shellcheck disable=SC2034 # read by armbian_kernel_config_apply_opts_from_arrays
	opts_y+=("ARM64_VA_BITS_39")
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
	else
		display_alert "$BOARD" "Enabling JM10-3588 upgrade lock dtb adn kernel" "info"
		chroot_sdcard apt-mark hold linux-image-vendor-rk35xx
		chroot_sdcard apt-mark hold linux-dtb-vendor-rk35xx
	fi

	# Hold the U-Boot package too, so an upgrade cannot swap the bootloader under
	# the board. BOOTCONFIG=none means no U-Boot package was built or installed
	# at all, and `apt-mark hold` exits 100 for a package that does not exist,
	# which would abort the whole build.
	if [[ "${BOOTCONFIG}" != "none" ]]; then
		chroot_sdcard apt-mark hold "linux-u-boot-yjh-jm10-3588-${BRANCH}"
	else
		display_alert "$BOARD" "Not holding a U-Boot package (BOOTCONFIG=none)" "info"
	fi

	display_alert "$BOARD" "Enabling rk3588-bluetooth.service" "info"
	chroot_sdcard_apt_get_install rfkill
	chroot_sdcard systemctl enable rk3588-bluetooth.service

	if [[ "${PROXMOX:-no}" != "yes" ]] && [[ ${JM10_DSA_88E6390} = "yes" ]] && [[ ${BRANCH} = "vendor" || ${BRANCH} = "legacy" ]] && [[ ${BUILD_DESKTOP} = "no" ]]; then
		#Only for Jm10 Hard Change. del /etc/netplan/10-dhcp-all-interfaces.yaml and add 10-dsa-MV88E6XXX-br0.yaml
		#桌面配置	网络使用NetworkManager,自行图形化配置网桥,暂不用10-dsa-MV88E6XXX-br0.yaml配置网桥
		display_alert "$BOARD" "Only for Jm10 Hard Change del 10-dhcp-all-interfaces.yaml and add 10-dsa-MV88E6XXX-br0.yaml" "info"
		rm -rf ${SDCARD}/etc/netplan/*.yaml
		# Generated from the shared port list in lib/functions/configuration/
		# jm10-network.sh, so the plain and PVE builds cannot drift apart. eth4
		# is not in that list: the board does not route it to a connector, and
		# enslaving a port with no PHY stops ifupdown2/networkd from bringing
		# br0 up at all.
		jm10_net_write_netplan_bridge "${SDCARD}/etc/netplan/10-dsa-MV88E6XXX-br0.yaml"
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
