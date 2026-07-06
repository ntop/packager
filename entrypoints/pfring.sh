#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: pfring

set -e

if [ "$1" = 'test' ]; then
    exec zcount -h
elif [ "$1" = 'version-check' ]; then
    # Do not check release as library may have an older release date; skip
    exit 0
elif [ "$1" = 'license-check' ]; then
    # pfring ZC licenses are tied to a NIC MAC address, not testable in this generic container; skip
    exit 0
elif [ "$1" = 'print-version' ]; then
    # pfring has no binary printing version only; skip
    exit 0
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
