# @description SquashFS + OverlayFS root filesystem. The rootfs is packed into a read-only `/boot/armbian/rootfs.squashfs` inside the image; at boot a `local-bottom` script auto-detects external storage (mSATA / SATA / USB disk), partitions and formats it on first boot, and stacks an OverlayFS upper on top of the SquashFS lower. The board keeps a tiny read-only root on eMMC/SD and every write lands on the external disk. Enabled automatically when `ROOTFS_TYPE=squashfs-overlay` is set in `main-config.sh`.
#
# Image layout (single ext4 partition, no separate /boot):
#   /boot/armbian/rootfs.squashfs   read-only lower, packed at build time
#   /boot/armbian/overlay.env       recorded build-time defaults (label, part, timeout)
#
# Runtime layout on the external disk (auto-detected at boot):
#   <disk>p1   ext4, label ARMBIAN_OVL, mounted at /run/overlay-upper
#   /run/overlay-upper/upper        overlay upperdir
#   /run/overlay-upper/work         overlay workdir
#   /run/overlay-upper/state        diagnostics (overlay.info)
#   /state/marker                   ownership marker (see "Safety" below)
#
# Safety -- the marker is the authorization, not the label:
#   A filesystem counts as OURS only when <upper>/state/marker exists and reads
#   "ARMBIAN_OVL_MARKER v1 uuid=<this filesystem's own UUID>". The label is only
#   a cheap pre-filter; 16 bytes of user-visible text is not proof of ownership.
#   The check is read-only (mount ro, read, umount) and runs BEFORE any write.
#
#   A disk is initialized only when it is PROVABLY BLANK: blkid finds no TYPE,
#   PTTYPE, LABEL or UUID on the whole disk. A disk holding data but no valid
#   marker is skipped and left completely untouched -- the root simply stays
#   read-only for that boot. The marker is stamped by format_partition() right
#   after mke2fs, so the next boot reclaims the disk instead of re-initializing
#   it and losing everything written in between.
#
#   Forcing SQUASHFS_OVERLAY_DISK does not bypass this: a non-blank disk without
#   a valid marker is refused, so a typo cannot wipe a live disk.
#
# Boot flow (see local-bottom/squashfs-overlay.sh for why local-bottom):
#   1. the kernel boots the ext4 underlay, initramfs mounts it read-only at ${rootmnt}
#   2. mountroot() leaves ${rootmnt} holding the underlay (which carries /boot)
#   3. local-bottom stacks overlayfs: lower = squashfs (loop), upper = external disk
#   4. run-init nukes the initramfs root and bind-mounts ${rootmnt} over /
#      (it skips anything with a different st_dev, so /run/... survives)
#
# Degraded modes, in order, all of which still boot:
#   no external disk found              -> root stays the read-only underlay
#   disk has data but no valid marker   -> skipped, untouched; root stays read-only
#   disk is provably blank              -> partitioned + formatted + marked, then used
#   no free loop device                 -> the underlay becomes the lower (writable)
#   overlay mount fails                 -> root stays the read-only underlay
#
# Vars:
#   SQUASHFS_COMPRESSION    zstd | xz | lzo | gzip        (default zstd)
#   SQUASHFS_OVERLAY_LABEL  ext4 label of the overlay fs    (default ARMBIAN_OVL)
#   SQUASHFS_OVERLAY_DISK   force a disk (e.g. /dev/sda)    (default: auto-detect)
#   SQUASHFS_OVERLAY_PART   partition number to create/use   (default 1)
#   SQUASHFS_OVERLAY_SIZE   unused at build time; reserved for a size hint
#   SQUASHFS_OVERLAY_TIMEOUT seconds to wait for a disk     (default 20)

# The underlay is a real filesystem the host must mount, and the one the image
# actually contains. squashfs-overlay is a *stack*, not an mkfs target, so
# prepare_partitions must not try to run `mkfs.squashfs-overlay`.
declare -g ROOTFS_MKFS_TYPE="ext4"

# squashfs-tools is needed on the build host to pack the lower.
function add_host_dependencies__add_squashfs_overlay_tooling() {
	display_alert "Extension: ${EXTENSION}: Adding packages to host dependencies" "squashfs-tools" "info"
	EXTRA_BUILD_DEPS+=("fs-tools::squashfs-tools")
}

function extension_prepare_config__prepare_squashfs_overlay() {
	# e2fsprogs is already in every Armbian image package list; ask for it
	# explicitly so the guarantee survives a list edit.
	display_alert "Extension: ${EXTENSION}: Adding extra packages to image" "e2fsprogs squashfs-tools" "info"
	add_packages_to_image e2fsprogs squashfs-tools

	if [[ -z "${SQUASHFS_COMPRESSION}" ]]; then
		declare -g SQUASHFS_COMPRESSION="zstd"
	fi
	case "${SQUASHFS_COMPRESSION}" in
		zstd | xz | lzo | gzip) ;;
		*) exit_with_error "Unknown SQUASHFS_COMPRESSION" "SQUASHFS_COMPRESSION=${SQUASHFS_COMPRESSION}" ;;
	esac

	[[ -z "${SQUASHFS_OVERLAY_LABEL}" ]] && declare -g SQUASHFS_OVERLAY_LABEL="ARMBIAN_OVL"
	# An ext4 label is at most 16 bytes and must not contain whitespace: it is
	# passed through blkid -t LABEL=... and into mke2fs -L.
	if [[ ! "${SQUASHFS_OVERLAY_LABEL}" =~ ^[A-Za-z0-9_.-]{1,16}$ ]]; then
		exit_with_error "SQUASHFS_OVERLAY_LABEL must be 1-16 chars of [A-Za-z0-9_.-]" "SQUASHFS_OVERLAY_LABEL=${SQUASHFS_OVERLAY_LABEL}"
	fi

	[[ -z "${SQUASHFS_OVERLAY_PART}" ]] && declare -g SQUASHFS_OVERLAY_PART="1"
	if ! [[ "${SQUASHFS_OVERLAY_PART}" =~ ^[0-9]+$ ]] || [[ "${SQUASHFS_OVERLAY_PART}" -lt 1 ]] || [[ "${SQUASHFS_OVERLAY_PART}" -gt 128 ]]; then
		exit_with_error "SQUASHFS_OVERLAY_PART must be an integer in 1..128" "SQUASHFS_OVERLAY_PART=${SQUASHFS_OVERLAY_PART}"
	fi

	[[ -z "${SQUASHFS_OVERLAY_TIMEOUT}" ]] && declare -g SQUASHFS_OVERLAY_TIMEOUT="20"
	if ! [[ "${SQUASHFS_OVERLAY_TIMEOUT}" =~ ^[0-9]+$ ]]; then
		exit_with_error "SQUASHFS_OVERLAY_TIMEOUT must be an integer (seconds)" "SQUASHFS_OVERLAY_TIMEOUT=${SQUASHFS_OVERLAY_TIMEOUT}"
	fi

	if [[ -n "${SQUASHFS_OVERLAY_DISK}" && ! "${SQUASHFS_OVERLAY_DISK}" =~ ^/dev/ ]]; then
		exit_with_error "SQUASHFS_OVERLAY_DISK must be an absolute /dev/ path" "SQUASHFS_OVERLAY_DISK=${SQUASHFS_OVERLAY_DISK}"
	fi

	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		exit_with_error "fs-squashfs-overlay-support enabled without ROOTFS_TYPE=squashfs-overlay" "ROOTFS_TYPE=${ROOTFS_TYPE}"
	fi

	# A boot partition is not required: the squashfs lives in /boot on the same
	# ext4 partition as the rootfs, exactly like a stock single-partition image.

	EXTRA_IMAGE_SUFFIXES+=("-squashfs")
}

# Both filesystems must be built-in (=y), not modules:
#   * the squashfs lower is mounted by the initramfs before / exists, and
#   * OverlayFS must already be present for the very first mount of /
# A module would need a root filesystem to be loaded from, which is what we are
# in the middle of creating.
#
# These are declared (not written into .config) for the same reason the JM10 DSA
# hook documents: custom_kernel_config runs after armbian_kernel_config, both
# append to the same opts_y array, and Kconfig resolves a choice to the last =y
# in file order -- so a hand-written .config entry placed earlier would lose.
function custom_kernel_config__squashfs_overlay_builtin_fs() {
	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		return 0
	fi
	display_alert "fs-squashfs-overlay-support" "Forcing built-in SquashFS + OverlayFS" "info"
	# shellcheck disable=SC2034 # read by armbian_kernel_config_apply_opts_from_arrays
	opts_y+=(
		"SQUASHFS"
		"SQUASHFS_ZSTD"
		"OVERLAY_FS"
		# The underlay partition holding /boot/armbian/rootfs.squashfs.
		"EXT4_FS"
	)
}

# The initramfs must be able to talk to external storage before / exists, and it
# must be able to format it. MODULES=most guesses from dependency probing and
# misses both, so the list is written explicitly. This file is also what
# /etc/initramfs-tools/modules in the image would be, so an update-initramfs run
# on the target keeps working.
function pre_customize_image__squashfs_overlay_initramfs_modules() {
	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		return 0
	fi
	display_alert "Extension: ${EXTENSION}: Pinning initramfs modules" "squashfs overlay ext4 + storage" "info"
	cat > "${SDCARD}/etc/initramfs-tools/modules" <<- 'EOF'
		# fs-squashfs-overlay-support: modules required before / can be mounted.
		# The stack itself -- both must be present, neither can be a module.
		squashfs
		overlay
		# The underlay partition that carries /boot/armbian/rootfs.squashfs.
		ext4
		# External storage: mSATA/SATA behind AHCI, NVMe, USB disks and UAS.
		ahci
		ata_piix
		nvme
		usb-storage
		uas
		# A whole disk with no partition table is still usable as the upper.
		loop
	EOF
	return 0
}

# Install the boot-time script and the initramfs-tools hook that pulls in
# mke2fs/fdisk/losetup/blkid. Both must be in place before update_initramfs()
# runs (which create_image_from_sdcard_rootfs does via pre_update_initramfs).
function pre_customize_image__install_squashfs_overlay_initramfs() {
	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		return 0
	fi

	local script_src="${EXTENSION_DIR}/local-bottom/squashfs-overlay.sh"
	[[ -f "${script_src}" ]] || exit_with_error "Missing initramfs script" "${script_src}"

	local script_dst="${SDCARD}/etc/initramfs-tools/scripts/local-bottom/squashfs-overlay.sh"
	mkdir -p "$(dirname "${script_dst}")"
	run_host_command_logged install -m 0755 "${script_src}" "${script_dst}"

	local hook_src="${EXTENSION_DIR}/initramfs-hook/squashfs-overlay-tools"
	local hook_dst="${SDCARD}/etc/initramfs-tools/hooks/squashfs-overlay-tools"
	if [[ -f "${hook_src}" ]]; then
		mkdir -p "$(dirname "${hook_dst}")"
		run_host_command_logged install -m 0755 "${hook_src}" "${hook_dst}"
	fi

	display_alert "Extension: ${EXTENSION}: Installed initramfs pieces" "local-bottom script + mke2fs/fdisk hook" "info"
	return 0
}

# Pack the finished rootfs into /boot/armbian/rootfs.squashfs while it is still
# mounted at ${MOUNT} (loop ${LOOP}).
#
# The squashfs is built from the mounted image, not from ${SDCARD}, so that
# everything the image stage produced is inside it: the kernel and dtb under
# /boot, the initrd, boot.scr/armbianEnv.txt, the finalized /etc/fstab, and the
# whole rootfs rsynced in by create_image_from_sdcard_rootfs. Pseudo-filesystems
# are excluded the same way image-output-iso.sh does, so their mount points
# survive as empty directories.
function pre_umount_final_image__squashfs_overlay_pack() {
	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		return 0
	fi

	local squashfs_dir="${MOUNT}/boot/armbian"
	run_host_command_logged mkdir -p "${squashfs_dir}"

	# Record build-time defaults. The initramfs script reads these as a fallback
	# under the kernel command line, so editing armbianEnv.txt cannot desync the
	# image from what it actually contains.
	#
	# NOT a <<- heredoc: `<<-` strips leading *tabs* only, and any surviving
	# leading whitespace would break the parser. Written flush-left, and each
	# line is split on the first '=' -- `read -r key val` would put the whole
	# "KEY=value" into $key and leave $val empty, silently dropping every
	# default. Comment lines carry no '=' and are skipped.
	{
		echo "# Generated by fs-squashfs-overlay-support at image build time."
		echo "# The local-bottom script reads these; kernel command line overrides win."
		echo "SQUASHFS_OVERLAY_LABEL=${SQUASHFS_OVERLAY_LABEL}"
		echo "SQUASHFS_OVERLAY_DISK=${SQUASHFS_OVERLAY_DISK:-}"
		echo "SQUASHFS_OVERLAY_PART=${SQUASHFS_OVERLAY_PART}"
		echo "SQUASHFS_OVERLAY_SIZE=${SQUASHFS_OVERLAY_SIZE:-}"
		echo "SQUASHFS_OVERLAY_TIMEOUT=${SQUASHFS_OVERLAY_TIMEOUT}"
		echo "SQUASHFS_OVERLAY_MOUNT=/var/lib/armbian/overlay"
	} > "${squashfs_dir}/overlay.env"

	display_alert "Extension: ${EXTENSION}: Packing rootfs squashfs (${SQUASHFS_COMPRESSION})" "boot/armbian/rootfs.squashfs" "info"

	# The output is written straight into the tree being walked, and excluded
	# from the archive by the `boot/armbian/rootfs.squashfs` pattern below, so
	# mksquashfs cannot archive a growing copy of itself. Verified: the finished
	# archive contains 0 entries for that path. Writing it elsewhere and moving
	# it in afterwards would copy the whole image across filesystems for nothing.
	declare -a cmd
	cmd=(mksquashfs "${MOUNT}" "${squashfs_dir}/rootfs.squashfs"
		-noappend -comp "${SQUASHFS_COMPRESSION}" -no-progress -wildcards
		-e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" "var/tmp/*"
		"boot/armbian/rootfs.squashfs"
		"var/lib/armbian/overlay/*")
	declare squashfs_rc=0
	run_host_command_logged "${cmd[*]@Q}" || squashfs_rc=$?
	if [[ "${squashfs_rc}" -ne 0 ]]; then
		rm -f "${squashfs_dir}/rootfs.squashfs"
		exit_with_error "fs-squashfs-overlay-support: mksquashfs failed (exit ${squashfs_rc})"
	fi

	# Sanity: the archive must not contain itself, and it must be readable.
	if unsquashfs -ll "${squashfs_dir}/rootfs.squashfs" 2> /dev/null | grep -q "boot/armbian/rootfs.squashfs"; then
		exit_with_error "fs-squashfs-overlay-support: the squashfs archived itself" "check the exclude patterns"
	fi
	display_alert "Extension: ${EXTENSION}: Rootfs squashfs ready" "$(du -h "${squashfs_dir}/rootfs.squashfs" | cut -f1)" "ext"
	return 0
}

# Make the image boot the overlay stack instead of the underlay.
#
# Runs in post_umount_final_image, i.e. after prepare_partitions() has written
# rootdev/rootfstype into armbianEnv.txt and the boot script, so the values are
# corrected rather than overwritten by a later stage.
function post_umount_final_image__squashfs_overlay_boot_args() {
	if [[ "${ROOTFS_TYPE}" != "squashfs-overlay" ]]; then
		return 0
	fi

	local env_file="${SDCARD}/boot/armbianEnv.txt"

	# The underlay must not be mounted read-write by systemd: it holds a
	# read-only squashfs, and a rw mount would make the root look writable.
	# initramfs-tools' mountroot() already ran by the time the overlay is
	# stacked, so systemd must not try again either.
	local fstab="${SDCARD}/etc/fstab"
	if [[ -f "${fstab}" ]]; then
		display_alert "Extension: ${EXTENSION}: Neutralizing root fstab entry" "/etc/fstab" "info"
		run_host_command_logged sed -i \
			-e "'s|^[^#[:space:]][^[:space:]]*[[:space:]]/[[:space:]].*|# / is a SquashFS+OverlayFS root, mounted by the initramfs|'" \
			"${fstab}"
	fi

	if [[ -f "${env_file}" ]]; then
		display_alert "Extension: ${EXTENSION}: Setting squashfs-overlay boot args" "armbianEnv.txt" "info"

		# rootfstype stays ext4: the initramfs mounts the underlay to reach
		# /boot, and the overlay is stacked afterwards in local-bottom. Telling
		# the kernel `overlayfs` here would make mountroot() fail before the
		# squashfs is even reachable.
		if grep -q '^rootfstype=' "${env_file}"; then
			run_host_command_logged sed -i -e "'s|^rootfstype=.*|rootfstype=ext4|'" "${env_file}"
		else
			echo "rootfstype=ext4" >> "${env_file}"
		fi

		# armbian_overlay=1 is the script's opt-in. Without it the image boots
		# exactly like a stock one, off the read-only underlay.
		if ! grep -q '^extraargs=' "${env_file}"; then
			echo "extraargs=armbian_overlay=1" >> "${env_file}"
		elif ! grep -q 'armbian_overlay=1' "${env_file}"; then
			run_host_command_logged sed -i -e "'s|^extraargs=|extraargs=armbian_overlay=1 |'" "${env_file}"
		fi
	else
		display_alert "Extension: ${EXTENSION}: no armbianEnv.txt to patch" "${SDCARD}/boot" "wrn"
	fi

	return 0
}
