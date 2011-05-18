#!/bin/sh

# Script to automate the process of "rooting" the Palm Pre

### VARIABLES

SCRIPTNAME="$(basename $0)"
LOG=/tmp/${SCRIPTNAME}.log
MYUSER=""
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/opt/bin:/opt/sbin
ARCH=$(uname -m)
if [ "$ARCH" = "armv7l" ] ; then
	EMULATOR=0
	FEED_ARCH=cs08q1armel
	FEED_MACHINE=pre
else
	EMULATOR=1
	FEED_ARCH=i686g25
	FEED_MACHINE=pre-emulator
fi

### END of VARIABLES

### FUNCTIONS

# Name:        log
# Arguments:   Message
# Description: logs Message to $LOG
log() {
	echo "$@" >> $LOG
}


# Name:        yesno
# Arguments:   Question
# Description: Asks a yes/no Question, returns 1 for yes, 0 for no
yesno() {
	IN=""
	until [ -n "$IN" ] ; do
		read -p "${@} " IN
		case "$IN" in
			y|Y|yes|YES)	return 1;;
			n|N|no|NO)	return 0;;
			*)		IN="";;
		esac
	done
}


# Name:        error
# Arguments:   Message
# Description: Displays FAILED followed by Message
error() {
	echo "FAILED"
	log "ERROR: ${@}"
	echo "$@"
	echo
	echo "Please paste the contents of ${LOG} to http://webos.pastebin.com/"
	echo "and seek help in the IRC channel #webos-internals."
	echo
	echo "To view ${LOG}, type:"
	echo
	echo "cat ${LOG}"
	echo
	echo
	return 1
}


# Name:        get_version
# Arguments:   Package
# Description: Checks to see if Package is installed, or if there is an upgrade
#              Returns 1 if the package is not installed or an upgrade is available,
#              0 otherwise.
get_version() {
	PKG=$1
	ipkg-opt info $PKG | grep -q "install user installed"
	RETURN="$?"
	if [ "$RETURN" -eq 0 ] ; then
		count=$(ipkg-opt info "$PKG" | grep Status: | wc -l)
	fi
	if [ "$RETURN" -eq 1 ] || [ $count -gt 1 ] ; then
		return 1
	else
		return 0
	fi
}


# Name:        getipkginfo
# Arguments:   none
# Description: Downloads the ipkg-opt Package file
getipkginfo() {
	if [ -f /tmp/Packages ] ; then
		log "Removing existing Package file: "
		echo -n "Removing existing Package file: "
		rm -f /tmp/Packages || error "Failed to remove /tmp/Package" || return 1
		log "OK"
		echo "OK"
	fi
	log "Downloading the ipkg-opt Package file from the Optware package feed: "
	echo -n "Downloading the ipkg-opt Package file from the Optware package feed: "
	cd /tmp || error "Failed to change directory to /tmp" || return 1
	wget http://ipkg.nslu2-linux.org/feeds/optware/${FEED_ARCH}/cross/unstable/Packages >> "$LOG" 2>&1 || error "Failed to download Packages file" || return 1
	log "OK"
	echo "OK"
}


# Name:        updateipkg
# Arguments:   none
# Description: Update the Optware package database
updateipkg() {
	log "Updating the Optware package database: "
	echo -n "Updating the Optware package database: "
	ipkg-opt update >> "$LOG" 2>&1 || error "Failed to update the local Optware package database" || return 1
	log "OK"
	echo "OK"
}


# Name:        installpkg
# Arguments:   Package [Package1] [Package2] [...]
# Description: Installs Package
installpkg() {
	if [ "$#" -lt 1 ] ; then
		return 1
	fi
	for pkg in "$@" ; do
		log "Installing ${pkg}: "
		echo -n "Installing ${pkg}: "
		ipkg-opt install "$pkg" >> "$LOG" 2>&1 || error "Failed to install ${pkg}" || return 1
		log "OK"
		echo "OK"
	done
}


# Name:        mkpatchdir
# Arguments:   none
# Description: Create a directory to contain the local clone of the webos-internals modifications repo
mkpatchdir() {
	log "Creating local patch directory: "
	echo -n "Creating local patch directory: "
	mkdir -p /opt/src/patches || error "Failed to create /opt/src/patches" || return 1
	sed -ire 's|^[\s#]*QUILT_PATCHES=.*|QUILT_PATCHES=/opt/src/patches|' /opt/etc/quilt.quiltrc || error "Failed to update /opt/etc/quilt.quiltrc" || return 1
	log "OK"
	echo "OK"
}


# Name:        getpatches
# Arguments:   none
# Description: Create local clone of the webos-internals modifications repo
getpatches() {
	log "Creating a local clone of the webos-internals modifications repository: "
	echo -n "Creating a local clone of the webos-internals modifications repository: "
	cd /opt/src || error "Failed to change directory to /opt/src" || return 1
	git clone git://gitorious.org/webos-internals/modifications.git > /dev/null 2>&1 || error "Failed to create the local clone" || return 1
	log "OK"
	echo "OK"
}

### END FUNCTIONS


# Mount the root fs rw
if [ "$EMULATOR" = 0 ] ; then
    log "Mounting the root file system read-write: "
    echo -n "Mounting the root file system read-write: "
    mount -o rw,remount / >> "$LOG" 2>&1 || error "Failed to mount / read/write" || exit 1
    log "OK"
    echo "OK"
fi

# Download the latest Package file
getipkginfo || exit 1

# Update the Optware package database
updateipkg || exit 1

# Check that git is installed, and if not, or if there is an upgrade, install it
get_version git
if [ "$?" -eq 1 ] ; then
	installpkg git || exit 1
else
	log "git is already installed and no upgrades are available"
	echo "git is already installed and no upgrades are available"
fi

# Check that quilt is installed, and if not, or if there is an upgrade, install it
get_version quilt
if [ "$?" -eq 1 ] ; then
	log "Installing quilt will take some time, please be patient ..."
	echo "Installing quilt will take some time, please be patient ..."
	installpkg quilt || exit 1
else
	log "quilt is already installed and no upgrades are available"
	echo "quilt is already installed and no upgrades are available"
fi

# Check that /opt/etc/quilt.quiltrc is configured, and if not, do so
echo -n "Checking that quilt is properly configured: "
touch /opt/etc/quilt.quiltrc || error "Failed to update /opt/etc/quilt.quiltrc" || exit 1
grep -v ^\# /opt/etc/quilt.quiltrc | grep -q "QUILT_PATCHES=/opt/src/patches"
if [ "$?" -ne 0 ] ; then
	sed -ire 's|^[\s#]*QUILT_PATCHES=.*|QUILT_PATCHES=/opt/src/patches|' /opt/etc/quilt.quiltrc || error "Failed to update /opt/etc/quilt.quiltrc" || exit 1
else
	log "OK"
	echo "OK"
	log "/opt/etc/quilt.quiltrc is already configured"
	echo "/opt/etc/quilt.quiltrc is already configured"
fi

mkpatchdir

# Clone (or update) the webos-internals modifications repository
if [ -d /opt/src/modifications ] ; then
	log "Updating the local clone of the webos-internals modifications repository: "
	echo -n "Updating the local clone of the webos-internals modifications repository: "
	cd /opt/src/modifications || error "Failed to change directory to /opt/src/modifications" || exit 1
	git pull >> "$LOG" 2>&1
	if [ "$?" -ne 0 ] ; then
		log "FAILED"
		echo "FAILED"
		log "The local clone of the webos-internals modifications repository was not updated"
		echo "The local clone of the webos-internals modifications repository was not updated"
		log "Moving /opt/src/modifications aside, and recloning: "
		echo -n "Moving /opt/src/modifications aside, and recloning: "
		cd /opt/src|| error "Failed to change directory to /opt/src" || exit 1
		mv /opt/src/modifications  /opt/src/modifications.$$ || error "Failed to move aside /opt/src/modifications" || exit 1
		getpatches
		RETURN="$?"
		log "The old directory is now /opt/src/modifications.$$"
		echo "The old directory is now /opt/src/modifications.$$"
		if [ "$RETURN" -eq 1 ] ; then
			exit 1
		fi
	else
		log "OK"
		echo "OK"
	fi
else
	getpatches || exit 1
fi

echo
log "Setup complete"
echo "Setup complete"
