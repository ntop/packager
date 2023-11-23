#!/bin/bash

#
# (C) 2020 - ntop.org
#
# This script removes all the installed ntop packages
#

PACKAGES="cento e1000e-zc-dkms fm10k-zc-dkms i40e-zc-dkms ice-zc-dkms igb-zc-dkms ixgbevf-zc-dkms ixgbe-zc-dkms n2disk n2n nbox ndpi ndpi-dev nedge nprobe nprobe-agent nprobe-dev nprobes nscrub ntopng ntopng-data nedge ntap pfring pfring-dkms pfring-drivers-zc-dkms nboxui ntop-license"

# Deinstall as last package
PACKAGES="$PACKAGES apt-ntop apt-ntop-stable"

# Check if the script is running as root
if [ "$EUID" -ne 0 ]
then
    echo "Please run the script as root to uninstall all ntop installed packages"
    exit
fi

# Switch on Distributions
if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu
    for package in $PACKAGES
    do
	# Function used to purge all the packages from input
	# ignoring the missing ones
	echo "Uninstalling $package..."
	apt-get -qq remove --ignore-missing $package > /dev/null 2>&1	
    done
elif [ -f /etc/redhat-release ]; then
    # CentOS/RedHat
    for package in $PACKAGES
    do
	# Check if the package is installed or not
	if rpm -q $package
	then
	    echo "Uninstalling $package"
	    # Remove the package without checking the dependencies
	    rpm -e --nodeps $package
	fi
    done
else
    echo "Distribution non recognized. Uninstall script unsuccessful."
fi
