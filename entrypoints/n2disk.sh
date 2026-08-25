#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: n2disk

set -e

if [ "$1" = 'test' ]; then
    disk2n -h
    exec n2disk -h
elif [ "$1" = 'version-check' ]; then
    TODAY=$(date +%y%m%d)
    VERSION_OUTPUT=$(n2disk --version 2>&1)
    echo "$VERSION_OUTPUT"
    if ! echo "$VERSION_OUTPUT" | grep -q "Version:.*\.$TODAY"; then
        echo "Version check FAILED: expected date $TODAY in version string"
        exit 1
    fi
elif [ "$1" = 'license-check' ]; then
    VERSION_OUTPUT=$(n2disk --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:\|Edition:"; then
        echo "License check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'license-mgr-check' ]; then
    LICENSE_MGR_CONF="/usr/share/ntop/etc/license-manager-client-n2disk.conf"
    VERSION_OUTPUT=$(n2disk --license-mgr "$LICENSE_MGR_CONF" --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License manager check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:\|Edition:"; then
        echo "License manager check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'print-version' ]; then
    n2disk --version
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
