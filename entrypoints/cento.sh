#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: cento

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    exec cento     -h
    exec cento-ids -h
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
