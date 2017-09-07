#!/bin/ksh -p
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2015 Joyent, Inc.
# Copyright 2017 ASS-Einrichtungssysteme GmbH, Inc.
#

#
# Customisation for SuSE-based distributions.  Assumes to have been
# sourced from lx_boot.
#

tmpfile=/tmp/lx-suse.$$

# Check that the directories we're writing to aren't symlinks outside the zone
safe_dir /etc
safe_dir /etc/init.d
safe_dir /etc/rc.d/rc0.d
safe_dir /etc/rc.d/rc1.d
safe_dir /etc/rc.d/rc2.d
safe_dir /etc/rc.d/rc3.d
safe_dir /etc/rc.d/rc4.d
safe_dir /etc/rc.d/rc5.d
safe_dir /etc/rc.d/rc6.d
safe_dir /etc/rc.d/rcS.d
safe_dir /etc/sysconfig
safe_dir /etc/sysconfig/network
safe_dir /etc/YaST2
safe_opt_dir /etc/selinux

# Populate resolve.conf setup files
zonecfg -z $ZONENAME info attr name=resolvers | awk '
BEGIN {
	print("# AUTOMATIC ZONE CONFIG")
}
$1 == "value:" {
	nres = split($2, resolvers, ",");
	for (i = 1; i <= nres; i++) {
		print("nameserver", resolvers[i]);
	}
}
' > $tmpfile
zonecfg -z $ZONENAME info attr name=dns-domain | awk '
$1 == "value:" {
	dom = $2
}
END {
	print("search", dom);
}
' >> $tmpfile
fnm=$ZONEROOT/etc/resolv.conf
if [[ -f $fnm || -h $fnm ]]; then
	mv -f $tmpfile $fnm
fi

# Override network configuration
#// for Loopback (lo) configuration
cat <<LOEOF > $ZONEROOT/etc/sysconfig/network/ifcfg-lo
# AUTOMATIC ZONE CONFIG
IPADDR=127.0.0.1/8
NETMASK=255.0.0.0
NETWORK=127.0.0.0
STARTMODE=nfsroot
BOOTPROTO=static
USERCONTROL=no
FIREWALL=no
LOEOF
#// prepare empty network configuration files
zonecfg -z $ZONENAME info net | egrep "physical:" | awk '{print $2}' | xargs -L 1 -I % touch $ZONEROOT/etc/sysconfig/network/ifcfg-%
#// for eth0 configuration
zonecfg -z $ZONENAME info net | awk '
BEGIN {
    print("# AUTOMATIC ZONE CONFIG");
}
$1 == "physical:" {
	print("# for interface:", $2)
    print("STARTMODE=auto")
    print("BOOTPROTO=dhcp")
    print("DHCLIENT_SET_DEFAULT_ROUTE=yes");
}
' > $tmpfile
fnm=$ZONEROOT/etc/sysconfig/network/ifcfg-eth0
if [[ -f $fnm || -h $fnm ]]; then
	mv -f $tmpfile $fnm
fi

#
# The default /etc/inittab might spawn mingetty on each of the virtual consoles
# as well as xdm on the X console.  Since we don't have virtual consoles nor
# an X console, spawn a single mingetty on /dev/console instead.
#
# Don't bother changing the file if it looks like we already did.
#
fnm=$ZONEROOT/etc/inittab
if ! egrep -s "Modified by lx brand" $fnm; then
	sed 's/^[1-6]:/# Disabled by lx brand: &/' \
	    $fnm > $tmpfile
	echo "1:2345:respawn:/sbin/getty 38400 console" >> $tmpfile
	echo "# Modified by lx brand" >> $tmpfile

	if [[ ! -h $fnm ]]; then
		mv -f $tmpfile $fnm
		chmod 644 $fnm
	fi
fi

# The SuSE init uses a combination of traditional rc-style service
# definitions and upstart-style definitions.

#
# The following rc-style scripts attempt to start services or otherwise
# configure the system in ways incompatible with zones, so don't execute them
# at boot time.
#
unsupported_rc_services="
	checkfs.sh
	checkroot.sh
	hwclock.sh
	kmod
	mtab.sh
	procps
	udev
	udev-mtab
"

for file in $unsupported_rc_services; do
	rm -f $ZONEROOT/etc/init.d/$file

	rc_files="$(echo $ZONEROOT/etc/rc[0-6S].d/[SK]+([0-9])$file)"

	if [[ "$rc_files" != \
	    "$ZONEROOT/etc/rc[0-6S].d/[SK]+([0-9])$file" ]]; then
		for file in $rc_files; do
			rm -f "$file"
		done
	fi
done

disable_svc()
{
	fnm=$ZONEROOT/etc/init/$1.override
	[[ -h $fnm || -f $fnm ]] && return
	echo "manual" > $fnm
}


#
# Now customize upstart
#

RMSVCS="
	network-interface-security
	udev
	udevmonitor
	udevtrigger
	udev-fallback-graphics
	udev-finish
"
for f in $RMSVCS
do
	disable_svc $f
done

#
# We need to setup for the /dev/shm mount. Unlike some other distros, SuSE
# can handle it as either /dev/shm or /run/shm. For simplicity we create an
# fstab entry to force it into the /dev/shm style.
#
fnm=$ZONEROOT/etc/fstab
entry=$(awk '{if ($2 == "/dev/shm") print $2}' $fnm)
if [[ -z "$entry" && ! -h $fnm ]]; then
    echo "swapfs    /dev/shm    tmpfs    defaults    0 0" >> $fnm
fi

#
# upstart modifications are complete
#
rm -f $tmpfile

# Hand control back to lx_boot
