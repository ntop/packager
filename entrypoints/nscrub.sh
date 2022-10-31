#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: nscrub

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    exec nscrub -h
else
    # can use this to run nscrub in the background for example
    exec "$@"
fi
