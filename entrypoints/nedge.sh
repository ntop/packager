#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: nedge

set -e

if [ "$1" = 'test' ]; then
    exec nedge -h
elif [ "$1" = 'version-check' ]; then
    TODAY=$(date +%y%m%d)
    VERSION_OUTPUT=$(nedge --version 2>&1)
    echo "$VERSION_OUTPUT"
    if ! echo "$VERSION_OUTPUT" | grep -q "Version:.*\.$TODAY"; then
        echo "Version check FAILED: expected date $TODAY in version string"
        exit 1
    fi
else
    # can use this to run nedge in the background for example
    exec "$@"
fi
