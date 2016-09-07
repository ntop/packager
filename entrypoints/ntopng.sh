#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: ntopng ntopng-data

set -e

if [ "$1" = 'test' ]; then
    exec ntopng -h
else
    # can use this to run ntopng in the background for example
    exec "$@"    
fi
