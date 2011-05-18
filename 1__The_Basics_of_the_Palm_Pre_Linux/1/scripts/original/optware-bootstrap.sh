#!/bin/sh

# optware-bootstrap.sh
# version 1.1.1
#
# Script to automate the process of permanently enabling Linux access
# 
# by Jack Cuyler (JackieRipper)
# jack at unixgeeks dot biz
#
# Features:
# 1.  Mounts the root file system read-write
# 2.  Creates and mounts /opt, and updates /etc/fstab
# 3.  Downloads and installs ipkg-opt
# 4.  Configures /opt/etc/ipkg/optware.conf
# 5.  Creates /etc/profile.d/optware
# 6.  Updates the Optware package database
# 7.  Create an unprivledged user
# 8.  Installs sudo
# 9.  Configures sudo privs for the user created above
# 10. Installs and configures dropbear
# 11. Installs openssh and openssh-sftp-server
# 12. Starts Dropbear
#
# Changelog:
#
# 0.1 Initial version
# 0.9 Added error checking, logging, and checks to see if each step is already done (JackieRipper, rwhitby, webos-internals IRC channel)
# 0.9.1 Bug fixes - missing mkdirs (oc80z)
# 0.9.2 Removed installation of git and quilt.  Will be a separate script (rwhitby)
# 0.9.3 Bug fix - "exit" should be "return" (JackieRipper)
# 0.9.4 Bug fixes - various bug fixes (JackieRipper and bclancy)
# 0.9.5 Added EMULATOR variable (rwhitby)
# 0.9.6 Added alternate /opt mount configuration if running on the emulator (rwhitby)
# 0.9.7 Bugfixes regarding ipkg-opt installation (Remailednet)
# 1.0.0 Start the Dropbear SSH daemon (nhahn)
# 1.1.0 Fix the disk mounting for the emulator (rwhitby)
# 1.1.1 Add NOPASSWD to sudoers for sftp-server

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


# Name:        mkopt
# Arguments:   none
# Description: Creates /var/opt and mounts it at /opt
mkopt() {
	log "Creating new /opt directory: "
	echo -n "Creating new /opt directory: "
	mkdir -p /var/opt || error "Failed to create /var/opt" || return 1
	mkdir -p /opt || error "Failed to create /opt" || return 1
	mount -o bind /var/opt /opt || error "Failed to mount /opt" || return 1
	log "OK"
	echo "OK"
}


# Name:        mkemuopt
# Arguments:   none
# Description: Mounts /dev/hdb at /opt
mkemuopt() {
	log "Creating new /opt directory: "
	echo -n "Creating new /opt directory: "
	mkdir -p /opt || error "Failed to create /opt" || return 1
	log "OK"
	echo "OK"
	log "Mounting /dev/hdb to /opt: "
	echo -n "Mounting /dev/hdb to /opt: "
	if [ ! -e /dev/hdb ] ; then
		error "/dev/hdb does not exist" || return 1
	fi
	if mount -t ext3 /dev/hdb /opt > /dev/null 2>&1 ; then
	    log "OK"
	    echo "OK"
	else
	    log "not formatted"
	    echo "not formatted"
	    log "Formatting /dev/hdb: "
	    echo -n "Formatting /dev/hdb: "
	    echo "y" | mkfs.ext3 -j /dev/hdb > /dev/null 2>&1 || error "Failed to format /dev/hdb" || return 1
	    log "OK"
	    echo "OK"
	    log "Mounting /dev/hdb to /opt: "
	    echo -n "Mounting /dev/hdb to /opt: "
	    mount -t ext3 /dev/hdb /opt || error "Failed to mount /dev/hdb" || return 1
	    log "OK"
	    echo "OK"
	fi
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
# Description: Downloads the ipkg-opt Package file, determines the latest version and md5sum of ipkg-opt 
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
	wget http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/cross/unstable/Packages >> "$LOG" 2>&1 || error "Failed to download Packages file" || return 1
	IPKG_FILE=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' Packages | awk '/^Filename:/ {print $2}')
	IPKG_SUM=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' Packages | awk '/^MD5Sum:/ {print $2}')
	if [ -z "$IPKG_FILE" ] ; then
		error "Could not determine the file name of the ipkg-opt package" || return 1
	fi
	if [ -z "$IPKG_SUM" ] ; then
		error "Could not determine the proper md5sum of the ipkg-opt package" || return 1
	fi
	echo "${IPKG_SUM}  ${IPKG_FILE}" > "${IPKG_FILE}.md5sum" || error "Failed to create ${IPKG_FILE}.md5sum" || return 1
	log "OK"
	echo "OK"
}


# Name:        getipkg
# Arguments:   none
# Description: Downloads and installs the ipkg-opt package
getipkg() {
	log "Downloading the latest ipkg-opt package from the Optware package feed: "
	echo -n "Downloading the latest ipkg-opt package from the Optware package feed: "
	cd /tmp || error "Failed to change directory to /tmp" || return 1
	wget "http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/cross/unstable/${IPKG_FILE}" >> "$LOG" 2>&1 || error "Failed to download ${IPKG_FILE}" || return 1
	log "OK"
	echo "OK"
	log "Checking the md5sum of "
	echo -n "Checking the md5sum of "
	md5sum -c "${IPKG_FILE}.md5sum" >> "$LOG" 2>&1
	md5sum -c "${IPKG_FILE}.md5sum" || return 1
	log "Installing the ipkg-opt package: "
	echo -n "Installing the ipkg-opt package: "
	mkdir -p /tmp/ipkg-opt || error "Failed to create /tmp/ipkg-opt" || return 1
	cd /tmp/ipkg-opt || error "Failed to cd to /tmp/ipkg-opt" || return 1
	tar xzf ../"$IPKG_FILE" || error "Failed to unpack ${IPKG_FILE}" || return 1
	cd / || error "Failed to change directory to /" || return 1
	tar xzf /tmp/ipkg-opt/data.tar.gz || error "Failed to unpack data.tar.gz" || return 1
	log "OK"
	echo "OK"
	log "Cleaning up temporary files: "
	echo -n "Cleaning up temporary files: "
	rm /tmp/"$IPKG_FILE"
	rm /tmp/"${IPKG_FILE}.md5sum"
	rm -rf /tmp/ipkg
	log "OK"
	echo "OK"
}


# Name:        doprofile
# Arguments:   none
# Description: Sets up /etc/profile.d/
doprofile() {
	log "Adding /opt/bin to the default \$PATH: "
	echo -n "Adding /opt/bin to the default \$PATH: "
	mkdir -p /etc/profile.d || error "Failed to create /etc/profile.d" || return 1
	cat <<EOF > /etc/profile.d/optware
PATH=\$PATH:/opt/bin
if [ "\`id -u\`" -eq 0 ]; then
	PATH=\$PATH:/opt/sbin
fi
EOF
	if [ "$?" -ne 0 ] ; then
		error "Failed to create /etc/profile.d/optware" || return 1
	fi
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


# Name:        mkuser
# Arguments:   none
# Description: Interactively create a regular user
mkuser() {
	log "Creating an unprivileged user account to be used when logging in..."
	echo
	echo
	echo "Creating an unprivileged user account to be used when logging in..."
	until [ -n "$MYUSER" ] ; do
		read -p "Enter the username of your unprivileged user: " MYUSER
		if [ -n "$MYUSER" ] ; then
			check=$(echo "$MYUSER" | tr -d '[a-z]')
			if [ "$MYUSER" = "$check" ] ; then
				echo "\"$USERNAME\" is an invalid username"
				echo "Usernames must contain at least 1 letter"
				MYUSER=""
			fi
			if [ -n "$MYUSER" ] ; then
				check=$(echo "$MYUSER" | tr -d '[A-Z][a-z][0-9]-_')
				if [ -n "$check" ] ; then
					echo "\"$USERNAME\" is an invalid username"
					echo "Usernames may only contain letters, numbers, dashes (-) and underscores (_)"
					MYUSER=""
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				check=$(echo "$MYUSER" | wc -c)
				if [ $check -lt 4 ] ; then
					echo "\"$USERNAME\" is an invalid username"
					echo "Usernames must contain at least 3 characters"
					MYUSER=""
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				LOWERUSER=$(echo "$MYUSER" | tr '[A-Z]' '[a-z]')
				if [ "$MYUSER" != "$LOWERUSER" ] ; then
					echo "Usernames should be lowercase.  Using \"${LOWERUSER}\""
					MYUSER="$LOWERUSER"
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				grep -q ^"$MYUSER": /etc/passwd
				if [ "$?" -eq 0 ] ; then
					UUID=$(awk 'BEGIN {FS=":"} {if ($1 == "'"$MYUSER"'") print $3}' /etc/passwd)
					log "${MYUSER} is an existing username (UID: ${UUID})"
					echo "WARNING: ${MYUSER} is an existing username (UID: ${UUID})"
					if [ "$UUID" -lt 1001 ] ; then
						MYUSER=""
					else
						yesno "Would you like to create another account?"
						case "$?" in
							0)	log "Using ${MYUSER}.  No new user"
								NONEWUSER=yes
								echo
								echo
								return 0
								break;;
							1)	log "Not using ${MYUSER}"
								MYUSER="";;
						esac
					fi
				fi
			fi
			if [ -n "$MYUSER" ] ; then
				adduser -h /var/home/$MYUSER $MYUSER || MYUSER=""
			fi
		fi
	done
}


# Name:        dosudo
# Arguments:   Username
# Description: Grants sudo privs for Username
dosudo() {
	log "Enabling root privileges for ${MYUSER}: "
	echo -n "Enabling root privileges for ${MYUSER}: "
	chmod 640 /opt/etc/sudoers || error "Failed to set the permissions on /opt/etc/sudoers" || return 1
	echo "$MYUSER ALL=(ALL) ALL" >> /opt/etc/sudoers || error "Failed to update /opt/etc/sudoers" || return 1
	echo "$MYUSER ALL=NOPASSWD: /opt/libexec/sftp-server" >> /opt/etc/sudoers || error "Failed to update /opt/etc/sudoers" || return 1
	chmod 440 /opt/etc/sudoers || error "Failed to set the permissions on /opt/etc/sudoers" || return 1
	log "OK"
	echo "OK"
}


# Name:        installpkg
# Arguments:   Package1 [Package2] [Package3] [...]
# Description: Installs Package
installpkg() {
	for pkg in "$@" ; do
		log "Installing ${pkg}: "
		echo -n "Installing ${pkg}: "
		ipkg-opt install "$pkg" >> "$LOG" 2>&1 || error "Failed to install ${pkg}" || return 1
		log "OK"
		echo "OK"
	done
}


# Name:        dodropbear
# Arguments:   none
# Description: Configures dropbear's startup options
dodropbear() {
	if [ -f /etc/event.d/optware-dropbear ] ; then
		log "/etc/event.d/optware-dropbear exists"
		echo
		echo
		echo "/etc/event.d/optware-dropbear already exists"
		yesno "Would you like to replace it with the latest version?"
		if [ "$?" -eq 0 ] ; then
			echo
			echo
			return
		else
			echo
			echo
			echo -n "Removing /etc/event.d/optware-dropbear: "
			rm /etc/event.d/optware-dropbear || error "Failed to remove /etc/event.d/optware-dropbear" || return 1
			log "Removed /etc/event.d/optware-dropbear"
			echo "OK"
		fi
	fi
	log "Configuring the Dropbear upstart script: "
	echo -n "Configuring the Dropbear upstart script: "
	cd /etc/event.d || error "Failed to change directory to /etc/event.d" || return 1
	wget http://gitorious.org/webos-internals/bootstrap/blobs/raw/master/etc/event.d/optware-dropbear >> "$LOG" 2>&1 \
		|| error "Failed to download optware-dropbear upstart script" || return 1
	log "OK"
	echo "OK"
	echo "How would you like to connect?"
	echo "1) WiFi"
	echo "2) EVDO"
	echo "3) Both WiFi and EVDO"
	ANS=""
	until [ -n "$ANS" ] ; do
		read -p "Selection: " ANS
		case "$ANS" in
			1) true;;
			2) sed -i '/INPUT/ s/ -i eth0/ -i ppp0/' /etc/event.d/optware-dropbear || error failed to update /etc/event.d/optware-dropbear || return 1;;
			3) sed -i '/INPUT/ s/ -i eth0//' /etc/event.d/optware-dropbear || error failed to update /etc/event.d/optware-dropbear || return 1;;
			*) ANS="";;
		esac
	done
}


### END FUNCTIONS


# Mount the root fs rw
#if [ "$EMULATOR" = 0 ] ; then
    log "Mounting the root file system read-write: "
    echo -n "Mounting the root file system read-write: "
    mount -o rw,remount / >> "$LOG" 2>&1 || error "Failed to mount / read/write" || exit 1
    log "OK"
    echo "OK"
#fi

if [ "$EMULATOR" = 0 ] ; then
	# Check to see if /opt is already a symlink to /var/opt, create it, if not
	opt_fscheck=$(awk '{ if ($1 == "/var/opt" && $2 == "/opt" && $3 == "bind") print $0}' /etc/fstab)
	opt_mntcheck=$(awk '{ if ($1 == "/dev/mapper/store-var" && $2 == "/opt") print $0}' /etc/mtab)
	
	if [ -z "$opt_mntcheck" ] ; then
		mkopt || exit 1
	fi

	if [ -z "$opt_fscheck" ] ; then
		log "Setting /opt to mount automatically at boot: "
		echo -n "Setting /opt to mount automatically at boot: "
		echo '/var/opt /opt bind defaults,bind 0 0' >> /etc/fstab || error "Failed to update /etc/fstab" || exit 1
		log "OK"
		echo "OK"
	fi
else
	# Check to see if /opt is /dev/hdb and mount it if not
	touch /etc/fstab
	opt_fscheck=$(awk '{ if ($1 == "/dev/hdb" && $2 == "/opt" && $3 == "ext3") print $0}' /etc/fstab)
	opt_mntcheck=$(awk '{ if ($1 == "/dev/hdb" && $2 == "/opt") print $0}' /etc/mtab)

	if [ -z "$opt_mntcheck" ] ; then
		mkemuopt || exit 1
	fi

	if [ -z "$opt_fscheck" ] ; then
		log "Setting /opt to mount automatically at boot: "
		echo -n "Setting /opt to mount automatically at boot: "
		echo '/dev/hdb /opt ext3 defaults 0 0' >> /etc/fstab || error "Failed to update /etc/fstab" || exit 1
		log "OK"
		echo "OK"
	fi
fi

# Download the Package file and check version
# If there is an upgrade, or if the package is not installed, install it.
getipkginfo || exit 1
if [ -x /opt/bin/ipkg-opt ] ; then
	ipkg_version=$(ipkg-opt --version 2>&1 | awk '{print $3}')
	ipkg_version_maj=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $1}')
	ipkg_version_min=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $2}')
	ipkg_version_rev=$(echo "$ipkg_version" | awk 'BEGIN {FS="[.-]"} {print $3}')
	ipkg_version_maj=${ipkg_version_maj:-0}
	ipkg_version_min=${ipkg_version_min:-0}
	ipkg_version_rev=${ipkg_version_rev:-0}
	IPKG_VERSION=$(awk 'BEGIN { RS = "" }; /^Package: ipkg-opt\n/ {print}' /tmp/Packages | awk '/^Version:/ {print $2}')
	IPKG_VERSION_MAJ=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $1}')
	IPKG_VERSION_MIN=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $2}')
	IPKG_VERSION_REV=$(echo "$IPKG_VERSION" | awk 'BEGIN {FS="[.-]"} {print $3}')
	
	if [ "$IPKG_VERSION_MAJ" -gt "$ipkg_version_maj" ] ; then
		INSTALL=yes
	elif [ "$IPKG_VERSION_MAJ" -eq "$ipkg_version_maj" ] ; then
		if [ "$IPKG_VERSION_MIN" -gt "$ipkg_version_min" ] ; then
			INSTALL=yes
		elif [ "$IPKG_VERSION_MIN" -eq "$ipkg_version_min" ] ; then
			if [ "$IPKG_VERSION_REV" -gt "$ipkg_version_rev" ] ; then
				INSTALL=yes
			fi
		fi
	fi
else
	INSTALL=yes
fi

if [ "$INSTALL" = "yes" ] ; then
	getipkg
else
	log "The ipkg-opt package is already installed, and there are no upgrades available"
	echo "The ipkg-opt package is already installed, and there are no upgrades available"
fi

# Configure the Optware feeds
if [ ! -f /opt/etc/ipkg/optware.conf ] ; then
	mkdir -p /opt/etc/ipkg || error "Failed to create /opt/etc/ipkg" || exit 1
fi
touch /opt/etc/ipkg/optware.conf || error "Failed to modify /opt/etc/ipkg" || exit 1
NOTIFIED=no
grep -q "^src/gz cross http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/cross/unstable$" /opt/etc/ipkg/optware.conf
if [ "$?" -ne 0 ] ; then
	log "Configuring the Optware feeds: "
	echo -n "Configuring the Optware feeds: "
	NOTIFIED=yes
	echo "src/gz cross http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/cross/unstable" >> /opt/etc/ipkg/optware.conf \
		|| error "Failed to update  /opt/etc/ipkg/optware.conf" || exit 1
fi
if [ "$EMULATOR" = 0 ] ; then
    grep -q "^src/gz native http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/native/unstable$" /opt/etc/ipkg/optware.conf
    if [ "$?" -ne 0 ] ; then
	if [ "$NOTIFIED" = "no" ] ; then
		log "Configuring the Optware feeds: "
		echo -n "Configuring the Optware feeds: "
	fi
	NOTIFIED=yes
	echo "src/gz native http://ipkg.nslu2-linux.org/feeds/optware/$FEED_ARCH/native/unstable" >> /opt/etc/ipkg/optware.conf \
		|| error "Failed to update  /opt/etc/ipkg/optware.conf" || exit 1
    fi
fi
grep -q "^src/gz kernel http://ipkg.nslu2-linux.org/feeds/optware/$FEED_MACHINE/cross/unstable$" /opt/etc/ipkg/optware.conf
if [ "$?" -ne 0 ] ; then
	if [ "$NOTIFIED" = "no" ] ; then
		log "Configuring the Optware feeds: "
		echo -n "Configuring the Optware feeds: "
	fi
	NOTIFIED=yes
	echo "src/gz kernel http://ipkg.nslu2-linux.org/feeds/optware/$FEED_MACHINE/cross/unstable" >> /opt/etc/ipkg/optware.conf \
		|| error "Failed to update  /opt/etc/ipkg/optware.conf" || exit 1
fi

if [ "$NOTIFIED" = "yes" ] ; then
	log "OK"
	echo "OK"
else
	log "/opt/etc/ipkg/optware.conf is already up to date"
	echo "/opt/etc/ipkg/optware.conf is already up to date"
fi


# Check that /opt/bin and /opt/sbin are part of the default $PATH, and if not, make it so
if [ ! -f /etc/profile.d/optware ] ; then
	mkdir -p /etc/profile.d || error "Failed to create /etc/profile.d" || exit 1
fi
touch /etc/profile.d/optware || error "Failed to modify /etc/profile.d/optware" || exit 1
grep PATH= /etc/profile.d/optware | grep -q "/opt/bin"
RESULT_A="$?"
grep PATH= /etc/profile.d/optware | grep -q "/opt/sbin"
RESULT_B="$?"

if [ "$RESULT_A" -ne 0 ] || [ "$RESULT_B" -ne 0 ] ; then
	doprofile || exit 1
else
	log "/etc/profile.d/optware is already up to date"
	echo "/etc/profile.d/optware is already up to date"
fi


# Update the Optware package database (we can do this no matter what)
updateipkg || exit 1

# Create an unprivledged user (we can do this no matter what, as we'll accept
# an existing user, as long as the UID is greater than 1000
#if [ "$EMULATOR" = 0 ] ; then
    mkuser || exit 1
#fi

# Check that sudo is installed, and if not, or if there is an upgrade available, install it
#if [ "$EMULATOR" = 0 ] ; then
    get_version sudo
    if [ "$?" -eq 1 ] ; then
	installpkg sudo || exit 1
    else
	log "sudo is already installed and no upgrades are available"
	echo "sudo is already installed and no upgrades are available"
    fi
#fi

# Check that root privileges are enabled for our user, and if not, make it so
#if [ "$EMULATOR" = 0 ] ; then
    if [ ! -f /opt/etc/sudoers ] ; then
	mkdir -p /opt/etc || error "Failed to create /opt/etc" || exit 1
    fi
    touch /opt/etc/sudoers || error "Failed to modify /opt/etc/sudoers" || exit 1

    check=$(awk '{ if ($1 == "'"$MYUSER"'" && $2 == "ALL=(ALL)" && $NF == "ALL") print $0}' /opt/etc/sudoers)
    if [ -z "$check" ] ; then
	 dosudo || exit 1
    else
	log "/opt/etc/sudoers is already up to date"
	echo "/opt/etc/sudoers is already up to date"
    fi
#fi

# Check that dropbear is installed, and if not, or if there is an upgrade available, install it
#if [ "$EMULATOR" = 0 ] ; then
    get_version dropbear
    if [ "$?" -eq 1 ] ; then
	installpkg dropbear || exit 1
	pkill dropbear > /dev/null 2>&1
	pkill -9 dropbear > /dev/null 2>&1
	dodropbear || exit 1
    else
	log "Dropbear is already installed and no upgrades are available"
	echo "Dropbear is already installed and no upgrades are available"
    fi
#fi

# Check that openssh is installed, and if not, or if there is an upgrade, install it
get_version openssh
if [ "$?" -eq 1 ] ; then
	installpkg openssh || exit 1
	pkill sshd > /dev/null 2>&1
	pkill -9 sshd > /dev/null 2>&1
else
	log "OpenSSH is already installed and no upgrades are available"
	echo "OpenSSH is already installed and no upgrades are available"
fi

# Check that openssh-sftp-server is installed, and if not, or if there is an upgrade, install it
get_version openssh-sftp-server
if [ "$?" -eq 1 ] ; then
	installpkg openssh-sftp-server || exit 1
else
	log "OpenSSH sFTP server is already installed and no upgrades are available"
	echo "OpenSSH sFTP server is already installed and no upgrades are available"
fi

if [ "$EMULATOR" = 0 ] ; then
    log "Starting the Dropbear SSH daemon:"
    echo -n "Starting the Dropbear SSH daemon:"
    initctl start optware-dropbear >> "$LOG" 2>&1 || error "Failed to start the Dropbear SSH daemon:" || exit 1
    log "OK"
    echo "OK"
fi

echo
log "Setup complete"
echo "Setup complete"
