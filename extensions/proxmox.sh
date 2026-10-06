# @description Builds a Proxmox VE 9 host image from Debian Trixie on amd64/arm64. Set `PROXMOX=yes` to install the official no-subscription userspace while retaining the Armbian kernel, add ZFS DKMS, select ifupdown2 networking with a DHCP `vmbr0`, and default the hostname to `pve`.

function extension_prepare_config__proxmox() {
	if [[ "${DISTRIBUTION}" != "Debian" || "${RELEASE}" != "trixie" ]]; then
		exit_with_error "Proxmox VE 9 requires Debian Trixie" "${DISTRIBUTION} ${RELEASE}"
	fi

	case "${ARCH}" in
		amd64 | arm64) ;;
		*) exit_with_error "Proxmox VE 9 supports amd64 and arm64 only" "ARCH=${ARCH}" ;;
	esac

	remove_packages network-manager network-manager-openvpn network-manager-gnome netplan.io
	EXTRA_IMAGE_SUFFIXES+=("-proxmox")
	if [[ -z "${EXTRA_ROOTFS_MIB_SIZE}" || "${EXTRA_ROOTFS_MIB_SIZE}" -lt 4096 ]]; then
		declare -g EXTRA_ROOTFS_MIB_SIZE=4096
	fi
}

function extension_finish_config__proxmox_require_kernel_headers() {
	[[ "${CONFIG_DEFS_ONLY}" == "yes" ]] && return 0

	if [[ "${KERNELSOURCE}" == "none" ]]; then
		exit_with_error "Proxmox VE requires an Armbian kernel" "KERNELSOURCE=none"
	fi
	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		exit_with_error "Proxmox with ZFS requires installable Armbian kernel headers" "${KERNEL_MAJOR_MINOR:-unknown}"
	fi
	# Consumed by the kernel package installation pipeline outside this extension.
	# shellcheck disable=SC2034
	declare -g INSTALL_HEADERS="yes"
}

function pre_customize_image__proxmox_network_setup() {
	mkdir -p "${SDCARD}/etc/network/interfaces.d" "${SDCARD}/etc/network/ifupdown2"
	rm -f "${SDCARD}"/etc/netplan/*.yaml "${SDCARD}"/etc/netplan/*.yml
	# Some base images do not ship every networking unit. The helper keeps the
	# diagnostic output but can still return 1 when there is nothing to report.
	disable_systemd_service_sdcard NetworkManager.service NetworkManager-wait-online.service systemd-networkd.service systemd-networkd-wait-online.service || true
	run_host_command_logged cp -pv "${SRC}/extensions/proxmox/interfaces" "${SDCARD}/etc/network/interfaces"
	chmod 644 "${SDCARD}/etc/network/interfaces"
}

function proxmox_remove_enterprise_sources() {
	# pve-manager's postinst may add the enterprise repository after the first
	# package transaction. Keep the image on the no-subscription repository and
	# prevent a stale/malformed base-image file from breaking later APT calls.
	rm -f "${SDCARD}/etc/apt/sources.list.d/pve-enterprise.sources" \
		"${SDCARD}/etc/apt/sources.list.d/pve-enterprise.list"
}

function post_repo_customize_image__install_proxmox() {
	local key_file="${SDCARD}/usr/share/keyrings/proxmox-archive-keyring.gpg"
	local repo_file="${SDCARD}/etc/apt/sources.list.d/pve-install-repo.sources"
	local pin_file="${SDCARD}/etc/apt/preferences.d/armbian-proxmox-no-kernel.pref"
	local debconf_file="${SDCARD}/tmp/proxmox-debconf"

	display_alert "Installing Proxmox VE" "official no-subscription repository; Armbian kernel retained" "info"
	mkdir -p "${SDCARD}/usr/share/keyrings" "${SDCARD}/etc/apt/sources.list.d" "${SDCARD}/etc/apt/preferences.d"
	# Base images may carry an enterprise source in either legacy `.list` or
	# deb822 `.sources` form. It can be malformed or require credentials, and
	# the no-subscription repository below is the only PVE source this image
	# needs.
	proxmox_remove_enterprise_sources
	run_host_command_logged curl --fail --location --silent --show-error \
		"https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg" \
		--output "${key_file}"
	chmod 644 "${key_file}"

	cat <<- EOF > "${repo_file}"
		Types: deb
		URIs: http://download.proxmox.com/debian/pve
		Suites: trixie
		Components: pve-no-subscription
		Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
	EOF

	# pve-manager recommends proxmox-ve, which would otherwise pull a second kernel.
	cat <<- EOF > "${pin_file}"
		Package: proxmox-ve proxmox-default-kernel proxmox-kernel-* proxmox-headers-*
		Pin: release *
		Pin-Priority: -1
	EOF

	cat <<- EOF > "${debconf_file}"
		postfix postfix/main_mailer_type select Local only
		postfix postfix/mailname string ${HOST}
	EOF
	chroot_sdcard debconf-set-selections /tmp/proxmox-debconf
	rm -f "${debconf_file}"

	do_with_retries 3 chroot_sdcard_apt_get_update
	# nss-myhostname resolves the default `pve` name to the DHCP address once
	# the bridge is up, without baking an incorrect build-host address into
	# /etc/hosts.
	chroot_sdcard_apt_get_install pve-manager ifupdown2 postfix open-iscsi chrony python3-mako libnss-myhostname

	proxmox_remove_enterprise_sources
	chroot_sdcard systemctl enable networking.service
	chroot_sdcard_apt_get_install zfs-dkms zfsutils-linux
	do_with_retries 3 chroot_sdcard_apt_get_update
}
