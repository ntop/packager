#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: pfring

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    echo "<test to be decided>"
elif [ "$1" = 'version-check' ]; then
    # pfring has no single user-space binary with a versioned release string; skip
    exit 0
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
