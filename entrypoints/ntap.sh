#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: ntap

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    exec ntap_collector -h
    exec ntap_remote -h
else
    # can use this to run ntap in the background for example
    exec "$@"
fi
