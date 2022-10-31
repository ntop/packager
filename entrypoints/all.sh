#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: pfring n2disk cento nprobe ntopng nscrub
# NOTE: we do not install nbox as it's not available on all platforms

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    echo "<test to be decided>"
else
    # can use this to run the software in the background for example
    exec "$@"
fi
