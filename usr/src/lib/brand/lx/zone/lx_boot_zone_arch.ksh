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
# Copyright 2017 Joyent, Inc.
# Copyright 2017 ASS-Einrichtungssysteme GmbH, Inc.
#

#
# Customisation for Arch-based distributions.  Assumes to have been
# sourced from lx_boot.
#

tmpfile=/tmp/lx-arch.$$


# Check that the directories we're writing to aren't symlinks outside the zone
safe_dir /etc
safe_opt_dir /etc/systemd
safe_opt_dir /etc/systemd/system
safe_opt_dir /etc/systemd/system/multi-user.target.wants

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

# network configuration
netdir="$ZONEROOT/etc/netctl"

# first cleanup potentially obsolete configuration
rm -f $netdir/interfaces-*

# Override network configuration for Loopback (lo) configuration
cat <<LOEOF > $netdir/interfaces-lo
# AUTOMATIC ZONE CONFIG
IPADDR=127.0.0.1/8
NETMASK=255.0.0.0
NETWORK=127.0.0.0
STARTMODE=nfsroot
BOOTPROTO=static
USERCONTROL=no
FIREWALL=no
LOEOF

zonecfg -z $ZONENAME info net | awk -v npath=$netdir '
$1 == "physical:" {
    fname = npath "/ifcfg-" $2
    print("# Automatic zone config for interface:", $2) > fname
    print("Interface=$2") >> fname
    print("Connection=ethernet") >> fname
    print("IP=dhcp") >> fname
}
$1 == "property:" && $2 == "(name=primary,value=\"true\")" {
    print("# primary") >> fname
}'

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

#
# We need to setup for the /dev/shm mount. Unlike some other distros, Arch
# can handle it as either /dev/shm or /run/shm. For simplicity we create an
# fstab entry to force it into the /dev/shm style.
#
fnm=$ZONEROOT/etc/fstab
entry=$(awk '{if ($2 == "/dev/shm") print $2}' $fnm)
if [[ -z "$entry" && ! -h $fnm ]]; then
    echo "swapfs    /dev/shm    tmpfs    defaults    0 0" >> $fnm
fi

#
# systemd modifications are complete
#
rm -f $tmpfile

# Hand control back to lx_boot
