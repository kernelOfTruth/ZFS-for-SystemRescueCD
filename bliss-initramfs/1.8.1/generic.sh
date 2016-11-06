#!/bin/busybox sh

# Simplified BSD License
#
# Copyright (C) 2013 Jonathan Vasquez <jvasquez1011@gmail.com> 
# All Rights Reserved
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met: 
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer. 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution. 
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Function to start rescue shell
rescue_shell()
{
	ewarn "Booting into rescue shell..."
	eline
	busybox --install -s
	exec setsid /bin/sh -c 'exec /bin/sh </dev/tty1 >/dev/tty1 2>&1'
}

# Function to load ZFS modules
load_modules()
{
        modules=""

        if [ "${USE_ZFS}" = "1" ]; then
                modules="${modules} spl icp zavl znvpair zcommon zunicode zfs"
        fi

        for x in ${modules}; do
                # If it's the ZFS module, and there is a arcmax set, then set the arc max to it
                if [ "${x}" = "zfs" ] && [ ! -z "${arcmax}" ]; then
                        modprobe ${x} zfs_arc_max=${arcmax}
                else
                        modprobe ${x}
                fi
        done
}

# Mount Kernel Devices
mnt_kernel_devs()
{
        mount -t proc none /proc
        mount -t devtmpfs none /dev
        mount -t sysfs none /sys
}

# Unmount Kernel Devices
umnt_kernel_devs()
{
        umount /proc
        umount /dev
        umount /sys
}

# Function for parsing command line options with "=" in them
get_opt() {
	echo "$@" | cut -d "=" -f 2
}

# Process command line options
parse_cmdline()
{
	for x in $(cat /proc/cmdline); do
		case ${x} in
		root\=*)
			root=$(get_opt ${x})
			;;
		init\=*)
			INIT=$(get_opt ${x})
			;;
		enc_root\=*)
			enc_root=$(get_opt ${x})
			;;
		nocache)
			nocache=1
			;;
		recover)
			recover=1
			;;
		refresh)
			refresh=1
			;;
		su)
			su=1
			;;
		esac
	done
}

# If USE_LUKS is enabled, run this function
luks_trigger()
{
        if [ -z "${enc_root}" ]; then
                die "You didn't pass the 'enc_root' variable to the kernel. Example: enc_root=/dev/sda2"
        fi
	
	eflag "Opening up your encrypted drive..."
        cryptsetup luksOpen ${enc_root} dmcrypt_root || die "luksOpen failed to open: ${enc_root}"
}

# If USE_ZFS is enabled, run this function
zfs_trigger()
{
        if [ -z "${root}" ]; then
		die "You must pass the root= variable. Example: root=rpool/ROOT/funtoo"
	fi

        pool_name="${root%%/*}"

        eflag "Mounting ${pool_name}..."

	local CACHE="/etc/zfs/zpool.cache"

	if [ ! -f "${CACHE}" ] || [ "${nocache}" = "1" ] || [ "${refresh}" = "1" ]; then
                remount_pool
	fi

        mount -t zfs -o zfsutil ${root} ${NEW_ROOT} || die "Failed to import your zfs root dataset"
}

# Self explanatory
switch_to_new_root()
{
        exec switch_root ${NEW_ROOT} ${INIT} || die "Failed to switch to your rootfs"
}

# Checks all triggers
check_triggers()
{
        if [ "${USE_LUKS}" = "1" ]; then
                luks_trigger
        fi

        if [ "${USE_ZFS}" = "1" ]; then
                zfs_trigger
        fi
}

# Regenerates a brand new zpool.cache file and installs it in the system
refresh_cache()
{
        eflag "Refreshing zpool.cache..."
	
        local CACHE="/etc/zfs/zpool.cache"

        check_triggers

        # If there is an old cache in the rootfs, then delete it.
        if [ -f "${NEW_ROOT}/${CACHE}" ]; then
                rm -f ${NEW_ROOT}/${CACHE}
        fi

        cp -f ${CACHE} ${NEW_ROOT}/${CACHE}

        ewarn "Please recreate your initramfs so that it can use the new zpool.cache!"
        sleep 5 

        # Now that we refreshed the cache, let's just continue into the OS
	have_a_nice_day
}

# Single User Mode
single_user()
{
        check_triggers
        chroot ${NEW_ROOT} /bin/bash --login
}

# Cleanly exports and imports pool

# I made this function since Gentoo/Funtoo don't cleanly umount the pool
# during shutdown/restart. This is actually only used if we aren't going to
# be using the zpool.cache.
remount_pool()
{
        zpool export -f ${pool_name}
        zpool import -N -o cachefile= ${pool_name} || die "Failed to import your pool: ${pool_name}"
}

# Central exit point needed to cleanly exit from either the main function
# or the refresh_cache function.
have_a_nice_day()
{
	einfo "Unmounting kernel devices..."
	umnt_kernel_devs || die "Failed to umount kernel devices"

	einfo "Switching to your rootfs..." && eline
	switch_to_new_root
}

### Utility Functions ###

# Used for displaying information
einfo()
{
        eline && echo -e "\e[1;32m>>>\e[0;m ${@}"
}

# Used for warnings
ewarn()
{
        eline && echo -e "\e[1;33m>>>\e[0;m ${@}"
}

# Used for flags
eflag()
{
        eline && echo -e "\e[1;34m>>>\e[0;m ${@}"
}

# Used for errors
die()
{
        eline && echo -e "\e[1;31m>>>\e[0;m ${@}" && rescue_shell 
}

# Prints empty line
eline()
{
        echo ""
}

# Welcome Message
welcome()
{
        einfo "Welcome to Bliss! [${VERSION}]"
}

# Prevent kernel from printing on screen
prevent_printk()
{
        echo 0 > /proc/sys/kernel/printk
}
