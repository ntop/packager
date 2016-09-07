#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: n2disk

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    exec pfcount   -h
    exec n2disk    -h
    exec n2disk10g -h
    exec disk2n    -h
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
