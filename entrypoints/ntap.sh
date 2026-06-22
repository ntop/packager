#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: ntap

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    exec ntap_collector -h
    exec ntap_remote -h
elif [ "$1" = 'version-check' ]; then
    TODAY=$(date +%y%m%d)
    VERSION_OUTPUT=$(ntap_collector --version 2>&1)
    echo "$VERSION_OUTPUT"
    if ! echo "$VERSION_OUTPUT" | grep -q "Version:.*\.$TODAY"; then
        echo "Version check FAILED: expected date $TODAY in version string"
        exit 1
    fi
elif [ "$1" = 'license-check' ]; then
    VERSION_OUTPUT=$(ntap_collector --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:"; then
        echo "License check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'print-version' ]; then
    ntap_collector --version
else
    # can use this to run ntap in the background for example
    exec "$@"
fi
