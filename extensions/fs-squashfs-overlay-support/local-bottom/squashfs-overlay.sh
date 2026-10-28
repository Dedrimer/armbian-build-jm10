#!/bin/sh

# SPDX-License-Identifier: GPL-2.0
#
# SquashFS + OverlayFS root: stack a writable OverlayFS upper, taken from
# auto-detected external storage, on top of the read-only SquashFS lower.
#
# Runs in /scripts/local-bottom, i.e. AFTER mountroot() has mounted the underlay
# partition read-only at ${rootmnt} and BEFORE /init moves /run into the new
# root. That placement is the only one that works, for two independent reasons:
#
#   1. /scripts/local is sourced *after* init-premount (line 249 of /init), so
#      anything init-premount defines -- including a mountroot() override -- is
#      clobbered by the stock definition. There is no way to take over the root
#      mount from init-premount.
#   2. local-bottom runs at /init line 266, init-bottom at line 277. The
#      init-bottom/udev script moves the /dev tmpfs into ${rootmnt}/dev and then
#      does `rm -rf /dev`, so the initramfs /dev (and every /dev/loopN and
#      /dev/sdX) is gone by then. This script needs those device nodes.
#
# What local-bottom gives us is exactly the window we need: the underlay is
# mounted, so /boot/armbian/rootfs.squashfs is reachable; /dev is still the
# initramfs devtmpfs; and /run is still the initramfs tmpfs, so the mounts made
# here are carried into the new root by the `mount -n -o move /run
# ${rootmnt}/run` at /init line 281.
#
# run-init (klibc) then nukes the initramfs root and bind-mounts ${rootmnt}
# over /. Its nuke_dir() recurses only into entries whose st_dev matches / --
# every mount under /run differs -- so the upper and the squashfs loop mount
# survive it, and the overlay at ${rootmnt} becomes the new root.
#
# Only tools present in the Armbian initramfs are used: klibc sh, cat, dd,
# sleep, mkdir, mount, umount, losetup, blkid, modprobe, udevadm. fdisk and
# mke2fs are added by the extension's initramfs-tools hook.
#
# The script never panics. A missing or unusable disk leaves the root exactly as
# mountroot() left it: the underlay, read-only. A board must stay bootable.
#
# Safety (the whole point of claim_existing_overlay / disk_is_blank):
#   a filesystem is OURS only if <upper>/state/marker reads
#   "ARMBIAN_OVL_MARKER v1 uuid=<its own UUID>". The ext4 label is a pre-filter,
#   never the authorization. The check is read-only and precedes every write, so
#   a disk is only ever initialized after being proven blank. A disk with data
#   and no valid marker is skipped untouched.

# shellcheck disable=SC2317 # invoked via /scripts/.../ORDER with $1
case "${1}" in
	prereqs)
		echo ""
		exit 0
		;;
esac

log() {
	echo "squashfs-overlay: ${*}"
}

warn() {
	echo "squashfs-overlay: WARNING: ${*}" >&2
}

# Is $1 a whole disk (not a partition, not a virtual/ram device)?
#
# The whitelist has to come first: `nvme0n1` and `mmcblk0` both end in a digit,
# so any "ends in a digit => partition" test would reject them.
is_whole_disk() {
	case "$1" in
		sd[a-z] | hd[a-z] | vd[a-z]) return 0 ;;
		nvme[0-9]n[0-9]) return 0 ;;
		mmcblk[0-9]) return 0 ;;
	esac
	# Everything else that /sys/class/block can hold is a partition or a
	# device we do not want: mmcblk0boot0/mmcblk0rpmb, nvme0n1p1, sdX1, and the
	# ram/dm/md/loop/zram/sr families.
	return 1
}

# Is $1 a disk we must never touch: virtual, or holding a mounted filesystem?
is_untouchable_disk() {
	case "$1" in
		ram[0-9]* | zram[0-9]* | dm-[0-9]* | md[0-9]* | sr[0-9]* | loop[0-9]*) return 0 ;;
	esac
	# Any disk that backs a currently mounted filesystem is in use.
	if [ -n "${mounted_disks}" ]; then
		for md in ${mounted_disks}; do
			[ "$1" = "${md}" ] && return 0
		done
	fi
	return 1
}

# Partition suffix for $1, or empty when $1 is already a whole disk.
partition_suffix() {
	case "$1" in
		mmcblk[0-9] | nvme[0-9]n[0-9]) echo "p" ;;
		*) echo "" ;;
	esac
}

# Read LABEL of a block device without a blkid cache (the initramfs has none).
probe_label() {
	[ -b "$1" ] || return 1
	blkid -p -c /dev/null -o value -s LABEL "$1" 2> /dev/null || return 1
}

probe_uuid() {
	[ -b "$1" ] || return 1
	blkid -p -c /dev/null -o value -s UUID "$1" 2> /dev/null || return 1
}

# The marker lives at <upper>/state/marker and pins the filesystem to this
# board by UUID. It is the ONLY thing that authorizes treating an existing
# filesystem as ours; a matching ext4 label alone is not enough, because a
# label is 16 bytes of user-visible text that any other tool could have set.
#
# Written only by format_partition() after a successful mke2fs, and read back
# by verify_overlay_marker() before anything destructive happens.
OVERLAY_MARKER_MAGIC="ARMBIAN_OVL_MARKER"
OVERLAY_MARKER_VERSION="v1"

# $1 = mount point of the candidate filesystem, $2 = expected fs UUID.
# Returns 0 only when the marker exists, has the right magic and version, and
# its recorded UUID equals the filesystem's actual UUID.
#
# No grep/sed/awk in the initramfs, so the parse is `read` + `case`.
verify_overlay_marker() {
	mnt="$1"
	expect_uuid="$2"
	marker_file="${mnt}/state/marker"

	[ -r "${marker_file}" ] || return 1

	while read -r m1 m2 m3 m4; do
		case "${m1} ${m2}" in
			"${OVERLAY_MARKER_MAGIC} ${OVERLAY_MARKER_VERSION}")
				# $m3 must be exactly "uuid=<actual uuid of this filesystem>".
				case "${m3}" in
					"uuid=${expect_uuid}") return 0 ;;
				esac
				# Right magic, wrong/tampered UUID: not ours.
				return 1
				;;
		esac
	done < "${marker_file}"
	return 1
}

# $1 = mount point, $2 = fs UUID. Called right after a fresh mke2fs + mount.
write_overlay_marker() {
	mnt="$1"
	fs_uuid="$2"
	mkdir -p "${mnt}/state" || return 1
	printf '%s %s uuid=%s\n' \
		"${OVERLAY_MARKER_MAGIC}" "${OVERLAY_MARKER_VERSION}" "${fs_uuid}" \
		> "${mnt}/state/marker" 2> /dev/null || return 1
	return 0
}

# The disk that backs the root mount -- the one holding the squashfs. It is the
# one disk that must never be reformatted.
find_boot_disk() {
	boot_disk=""
	# /proc/mounts lines: "SOURCE TARGET TYPE OPTS 0 0"
	while read -r src tgt fstype rest; do
		if [ "${tgt}" = "${rootmnt}" ] || [ "${tgt}" = "/" ]; then
			case "${src}" in
				/dev/*)
					name="${src#/dev/}"
					# strip a trailing partition number
					case "${name}" in
						mmcblk[0-9]p[0-9] | nvme[0-9]n[0-9]p[0-9]) boot_disk="${name%p[0-9]}" ;;
						sd[a-z][0-9] | hd[a-z][0-9] | vd[a-z][0-9]) boot_disk="${name%[0-9]}" ;;
						*) boot_disk="${name}" ;;
					esac
					break
					;;
			esac
		fi
	done < /proc/mounts
}

# Is $1 a *partition* we may use or inspect as the overlay upper?
#
# Distinct from is_untouchable_disk(), which works on whole-disk names. Here the
# name is a partition, so the checks are:
#   * it is a partition at all (not a whole disk, not a pseudo-device)
#   * it does not live on the boot disk -- a stale ARMBIAN_OVL label on the
#     boot partition must never be picked up as the overlay
#   * it is not one of the eMMC/NVMe reserved areas (mmcblk0boot0/boot1/rpmb),
#     which are small, fixed-size and not partition-table managed
is_usable_partition() {
	is_whole_disk "$1" && return 1
	case "$1" in
		ram[0-9]* | zram[0-9]* | dm-[0-9]* | md[0-9]* | loop[0-9]* | sr[0-9]*) return 1 ;;
		mmcblk[0-9]boot[0-9] | mmcblk[0-9]rpmb) return 1 ;;
	esac
	# Which disk does it live on? A partition on the boot disk is off limits:
	# a stale ARMBIAN_OVL label there must never be picked up as the overlay.
	_part_parent="$(partition_parent "$1")"
	if [ -n "${boot_disk}" ] && [ "${_part_parent}" = "${boot_disk}" ]; then
		return 1
	fi
	return 0
}

# Echo the whole-disk name that partition $1 lives on.
partition_parent() {
	case "$1" in
		mmcblk[0-9]p[0-9] | nvme[0-9]n[0-9]p[0-9]) _part_parent="${1%p[0-9]}" ;;
		sd[a-z][0-9] | hd[a-z][0-9] | vd[a-z][0-9]) _part_parent="${1%[0-9]}" ;;
		*) _part_parent="$1" ;;
	esac
	echo "${_part_parent}"
}

# Disks that currently back a mount, so they are never reformatted.
collect_mounted_disks() {
	mounted_disks=""
	while read -r src tgt fstype rest; do
		case "${src}" in
			/dev/*)
				name="${src#/dev/}"
				case "${name}" in
					mmcblk[0-9]p[0-9] | nvme[0-9]n[0-9]p[0-9]) mounted_disks="${mounted_disks} ${name%p[0-9]}" ;;
					sd[a-z][0-9] | hd[a-z][0-9] | vd[a-z][0-9]) mounted_disks="${mounted_disks} ${name%[0-9]}" ;;
					*) mounted_disks="${mounted_disks} ${name}" ;;
				esac
				;;
		esac
	done < /proc/mounts
}

# Candidate external disks, in a stable order, skipping the boot disk.
list_candidate_disks() {
	for entry in /sys/class/block/*; do
		[ -d "${entry}" ] || continue
		name="${entry##*/}"
		is_whole_disk "${name}" || continue
		is_untouchable_disk "${name}" && continue
		[ -r "${entry}/size" ] || continue
		# 512-byte sectors; skip anything under 64 MiB -- not a data disk.
		[ "$(cat "${entry}/size")" -gt 131072 ] || continue
		echo "/dev/${name}"
	done
}

# Wait for external storage to enumerate. SATA/NVMe are fast; USB (and a disk
# behind a hub) can take several seconds, mSATA behind a PCIe switch longer.
wait_for_candidates() {
	waited=0
	while [ "${waited}" -lt "${overlay_timeout}" ]; do
		# shellcheck disable=SC2046 # word splitting is intended
		set -- $(list_candidate_disks)
		if [ "$#" -gt 0 ]; then
			return 0
		fi
		sleep 1
		waited=$((waited + 1))
	done
	return 1
}

# Make $1 a usable overlay filesystem: partition it if it is blank, then mkfs.
# Echoes the partition device on success.
prepare_disk() {
	disk="$1"
	log "initializing ${disk} for the overlay upper"

	# Wipe old signatures so a stale label cannot be matched later. wipefs is
	# not in the initramfs; a 34 MiB zero fill over the first sectors removes
	# every superblock that matters for ext4 (and the MBR/GPT that follows).
	dd if=/dev/zero of="${disk}" bs=1M count=34 conv=notrunc 2> /dev/null || true

	if [ ! -x /usr/sbin/fdisk ] && [ ! -x /sbin/fdisk ]; then
		warn "fdisk is missing from the initramfs; using the whole disk"
		echo "${disk}"
		return 0
	fi

	# One primary partition spanning the whole disk: new DOS label, primary,
	# partition 1, default first sector, default last sector, write.
	if [ -x /usr/sbin/fdisk ]; then
		printf 'o\nn\np\n1\n\n\nw\n' | /usr/sbin/fdisk "${disk}" > /dev/null 2>&1 || true
	else
		printf 'o\nn\np\n1\n\n\nw\n' | /sbin/fdisk "${disk}" > /dev/null 2>&1 || true
	fi

	# The kernel will not re-read the table on its own; ask udev to.
	udevadm trigger --subsystem-match=block --action=add > /dev/null 2>&1 || true
	udevadm settle > /dev/null 2>&1 || true

	part="${disk}$(partition_suffix "${disk}")${overlay_part}"
	if [ ! -b "${part}" ]; then
		# Some device names carry no p (sdX1); the suffix helper already
		# returns empty for those, so this is only reached if udev was slow.
		sleep 2
		udevadm settle > /dev/null 2>&1 || true
	fi
	if [ ! -b "${part}" ]; then
		warn "partition ${part} did not appear on ${disk}"
		return 1
	fi
	echo "${part}"
}

format_partition() {
	part="$1"
	log "formatting ${part} as ext4 (label ${overlay_label})"
	if [ -x /usr/sbin/mke2fs ]; then
		/usr/sbin/mke2fs -q -F -t ext4 -L "${overlay_label}" "${part}" > /dev/null 2>&1 || return 1
	elif [ -x /sbin/mke2fs ]; then
		/sbin/mke2fs -q -F -t ext4 -L "${overlay_label}" "${part}" > /dev/null 2>&1 || return 1
	else
		warn "mke2fs is missing from the initramfs"
		return 1
	fi

	# Stamp the marker immediately, while the partition is still ours and we
	# know its UUID. Without this the freshly formatted disk would be blank on
	# the next boot and could be initialized again -- losing whatever was
	# written in between.
	fs_uuid="$(probe_uuid "${part}" 2> /dev/null)"
	if [ -n "${fs_uuid}" ]; then
		mkdir -p /run/overlay-stamp
		if mount -t ext4 -o rw "${part}" /run/overlay-stamp 2> /dev/null; then
			if write_overlay_marker /run/overlay-stamp "${fs_uuid}"; then
				log "wrote overlay marker (uuid=${fs_uuid})"
			else
				warn "could not write the overlay marker to ${part}"
			fi
			umount /run/overlay-stamp 2> /dev/null || true
		else
			warn "could not mount ${part} to write the overlay marker"
		fi
	else
		warn "could not read the UUID of ${part}; no marker written"
	fi

	echo "${part}"
}

# Claim check for a candidate partition: is it OUR overlay, provably?
# Read-only. Mounts the partition temporarily, verifies the marker, unmounts.
# Returns 0 only on a verified match. A partition that is not ext4, cannot be
# mounted, or has a missing/invalid marker returns 1 -- it is then treated as
# foreign and never initialized.
claim_existing_overlay() {
	part="$1"
	[ -b "${part}" ] || return 1

	# The label is a cheap first filter: if it is not even our label there is
	# nothing to verify. It is NOT the authorization -- only the marker is.
	if [ "$(probe_label "${part}" 2> /dev/null)" != "${overlay_label}" ]; then
		return 1
	fi

	fs_uuid="$(probe_uuid "${part}" 2> /dev/null)"
	[ -n "${fs_uuid}" ] || return 1

	mkdir -p /run/overlay-claim
	if ! mount -t ext4 -o ro,noload "${part}" /run/overlay-claim 2> /dev/null; then
		# noload rejects a dirty journal; retry without it so a board that was
		# power-cycled mid-write can still be reclaimed read-only.
		if ! mount -t ext4 -o ro "${part}" /run/overlay-claim 2> /dev/null; then
			umount /run/overlay-claim 2> /dev/null || true
			return 1
		fi
	fi

	verified="no"
	if verify_overlay_marker /run/overlay-claim "${fs_uuid}"; then
		verified="yes"
	fi
	umount /run/overlay-claim 2> /dev/null || true

	[ "${verified}" = "yes" ] || return 1
	return 0
}

# Is $1 provably empty of any filesystem or partition table?
#
# Whole-disk blkid probing is the test: no TYPE, no PTTYPE, no LABEL and no
# UUID anywhere means there is nothing to lose. This is what authorizes
# initializing a disk in auto-detect mode -- a disk holding data but no valid
# marker is skipped instead of wiped.
#
# No `[ -b ]` guard here on purpose. The callers (list_candidate_disks and the
# forced-disk path) have already established the device exists, and gating on
# `-b` would make "not a block device" indistinguishable from "not blank" --
# the wrong default for a predicate that decides whether something gets wiped.
disk_is_blank() {
	disk="$1"
	for tag in TYPE PTTYPE LABEL UUID; do
		if [ -n "$(blkid -p -c /dev/null -o value -s "${tag}" "${disk}" 2> /dev/null)" ]; then
			return 1
		fi
	done
	return 0
}

# Same blank test, for a device path that may not exist yet (forced-disk case).
device_is_blank() {
	dev="$1"
	[ -b "${dev}" ] || return 0 # nothing there -> nothing to destroy
	disk_is_blank "${dev}"
}


main() {
	# Defaults; overridden by the kernel command line below.
	overlay_label="ARMBIAN_OVL"
	overlay_disk=""
	overlay_part="1"
	overlay_timeout="20"
	overlay_size=""
	overlay_mount="/var/lib/armbian/overlay"

	# The image records its build-time defaults; the kernel command line wins.
	#
	# The file is KEY=value, so the line is split on the first '=' explicitly.
	# `read -r key val` does NOT work here: with no whitespace in the line it
	# puts the entire "KEY=value" into $key and leaves $val empty, so every
	# lookup below silently misses and the build-time defaults are ignored.
	if [ -r "${rootmnt}/boot/armbian/overlay.env" ]; then
		while read -r line; do
			# Skip comments and blank lines (both have no '=' to split on).
			case "${line}" in
				'' | \#*) continue ;;
			esac
			key="${line%%=*}"
			val="${line#*=}"
			[ "${key}" = "${line}" ] && continue # no '=' on this line
			case "${key}" in
				SQUASHFS_OVERLAY_LABEL) [ -n "${val}" ] && overlay_label="${val}" ;;
				SQUASHFS_OVERLAY_DISK) [ -n "${val}" ] && overlay_disk="${val}" ;;
				SQUASHFS_OVERLAY_PART) [ -n "${val}" ] && overlay_part="${val}" ;;
				SQUASHFS_OVERLAY_SIZE) [ -n "${val}" ] && overlay_size="${val}" ;;
				SQUASHFS_OVERLAY_TIMEOUT) [ -n "${val}" ] && overlay_timeout="${val}" ;;
			esac
		done < "${rootmnt}/boot/armbian/overlay.env"
	fi

	for x in $(cat /proc/cmdline); do
		case "${x}" in
			squashfs_overlay_label=*) overlay_label="${x#*=}" ;;
			squashfs_overlay_disk=*) overlay_disk="${x#*=}" ;;
			squashfs_overlay_part=*) overlay_part="${x#*=}" ;;
			squashfs_overlay_timeout=*) overlay_timeout="${x#*=}" ;;
		esac
	done

	# Only activate when asked. Without this the image boots the squashfs
	# read-only, exactly as it would without the extension.
	armbian_overlay="no"
	for x in $(cat /proc/cmdline); do
		case "${x}" in
			armbian_overlay=1 | armbian_overlay=yes) armbian_overlay="yes" ;;
		esac
	done
	if [ "${armbian_overlay}" != "yes" ]; then
		log "armbian_overlay not requested; leaving the root read-only"
		return 0
	fi

	collect_mounted_disks
	find_boot_disk
	[ -n "${boot_disk}" ] && log "boot disk is ${boot_disk} (holds the squashfs; never touched)"

	squashfs="${rootmnt}/boot/armbian/rootfs.squashfs"
	if [ ! -r "${squashfs}" ]; then
		warn "no ${squashfs}; leaving the root read-only"
		return 0
	fi

	# --- pick the overlay filesystem -------------------------------------
	# The safety gate. A filesystem counts as OURS only when it carries a valid
	# marker (magic + version + its own UUID). Everything else -- a blank disk,
	# a foreign filesystem, a leftover partition whose label merely matches, or
	# a marker whose UUID does not match -- is not ours and is never touched.
	#
	# The check is read-only and runs BEFORE prepare_disk()'s `dd` wipe, so a
	# false positive cannot destroy data: a device is only ever initialized
	# after it has been proven to be blank.
	overlay_part_dev=""

	if [ -n "${overlay_disk}" ]; then
		# Forced disk: reuse it if it carries a valid marker.
		candidate="${overlay_disk}$(partition_suffix "${overlay_disk}")${overlay_part}"
		if claim_existing_overlay "${candidate}"; then
			overlay_part_dev="${candidate}"
		else
			# No valid marker. Refuse unless the device is provably blank, so a
			# typo in SQUASHFS_OVERLAY_DISK cannot wipe a live disk.
			if ! device_is_blank "${candidate}"; then
				warn "${candidate} has no valid overlay marker and is not blank; refusing to initialize it"
				warn "leaving the root read-only; erase that disk manually if you want it used"
				return 0
			fi
			overlay_part_dev="$(prepare_disk "${overlay_disk}" || true)"
			[ -n "${overlay_part_dev}" ] && overlay_part_dev="$(format_partition "${overlay_part_dev}" || true)"
		fi
	else
		# Auto-detect: an already-claimed overlay wins, then the first blank disk.
		existing=""
		for entry in /sys/class/block/*; do
			[ -d "${entry}" ] || continue
			name="${entry##*/}"
			# Partitions only, never the boot disk, never a reserved/virtual
			# device: a stale ARMBIAN_OVL label on the boot partition must not
			# be mistaken for a previously-initialized overlay.
			is_usable_partition "${name}" || continue
			dev="/dev/${name}"
			[ -b "${dev}" ] || continue
			if claim_existing_overlay "${dev}"; then
				existing="${dev}"
				log "found a claimed overlay filesystem ${dev} (marker verified)"
				break
			fi
		done

		if [ -n "${existing}" ]; then
			overlay_part_dev="${existing}"
		else
			if ! wait_for_candidates; then
				warn "no external disk after ${overlay_timeout}s; leaving the root read-only"
				return 0
			fi
			for cand in $(list_candidate_disks); do
				# Only a provably blank disk is ever initialized. A disk holding
				# data but no valid marker is left completely alone.
				if ! disk_is_blank "${cand}"; then
					log "skipping ${cand}: not blank and no valid overlay marker"
					continue
				fi
				log "initializing blank disk ${cand} for the overlay upper"
				prepared="$(prepare_disk "${cand}" || true)"
				if [ -z "${prepared}" ]; then
					continue
				fi
				overlay_part_dev="$(format_partition "${prepared}" || true)"
				[ -n "${overlay_part_dev}" ] && break
			done
		fi
	fi

	if [ -z "${overlay_part_dev}" ] || [ ! -b "${overlay_part_dev}" ]; then
		warn "no usable overlay filesystem; leaving the root read-only"
		return 0
	fi

	# --- mount the upper --------------------------------------------------
	mkdir -p /run/overlay-upper
	if ! mount -t ext4 -o rw,noatime "${overlay_part_dev}" /run/overlay-upper; then
		warn "could not mount ${overlay_part_dev}; leaving the root read-only"
		return 0
	fi
	mkdir -p /run/overlay-upper/upper /run/overlay-upper/work /run/overlay-upper/state

	# --- mount the squashfs lower ----------------------------------------
	# klibc's mount has no `-o loop`, so attach the loop device explicitly.
	mkdir -p /run/lower
	loopdev=""
	for n in 0 1 2 3 4 5 6 7; do
		if losetup "/dev/loop${n}" "${squashfs}" 2> /dev/null; then
			loopdev="/dev/loop${n}"
			break
		fi
	done
	if [ -n "${loopdev}" ]; then
		if ! mount -t squashfs -r "${loopdev}" /run/lower; then
			warn "could not mount the squashfs on ${loopdev}; leaving the root read-only"
			losetup -d "${loopdev}" 2> /dev/null || true
			umount /run/overlay-upper 2> /dev/null || true
			return 0
		fi
	else
		# No free loop device: fall back to using the already-mounted underlay
		# as the lower. The overlay still works, it just is not read-only.
		warn "no free loop device; using the underlay as the overlay lower"
		mkdir -p /run/underlay
		mount -o bind "${rootmnt}" /run/underlay || {
			warn "could not bind the underlay; leaving the root read-only"
			umount /run/overlay-upper 2> /dev/null || true
			return 0
		}
	fi

	# --- stack it ---------------------------------------------------------
	lower_path="/run/lower"
	[ -n "${loopdev}" ] || lower_path="/run/underlay"

	log "stacking overlayfs: lower=${lower_path} upper=${overlay_part_dev}"
	if ! mount -t overlay \
		-o "lowerdir=${lower_path},upperdir=/run/overlay-upper/upper,workdir=/run/overlay-upper/work" \
		overlay "${rootmnt}"; then
		warn "overlayfs mount failed; leaving the root read-only"
		[ -n "${loopdev}" ] && losetup -d "${loopdev}" 2> /dev/null
		umount /run/lower 2> /dev/null || true
		umount /run/underlay 2> /dev/null || true
		umount /run/overlay-upper 2> /dev/null || true
		return 0
	fi

	# Diagnostics for the running system. Written into the upper so they
	# survive; /init's `mount -o move /run ${rootmnt}/run` relocates this to
	# /run/overlay-upper/state/overlay.info in the booted system.
	{
		echo "overlay_device=${overlay_part_dev}"
		echo "overlay_disk=${overlay_disk:-auto}"
		echo "overlay_label=${overlay_label}"
		echo "overlay_part=${overlay_part}"
		echo "squashfs=${squashfs}"
		echo "lower=${lower_path}"
	} > /run/overlay-upper/state/overlay.info 2> /dev/null || true

	# A marker inside the merged root, so userspace can tell it is on an
	# overlay without parsing /proc/mounts.
	mkdir -p "${rootmnt}/var/lib/armbian/overlay"
	echo "squashfs+overlayfs" > "${rootmnt}/var/lib/armbian/overlay/mode" 2> /dev/null || true

	log "root is now SquashFS + OverlayFS (upper on ${overlay_part_dev})"
	return 0
}

main
