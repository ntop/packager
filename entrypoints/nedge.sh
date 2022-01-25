#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: nedge

set -e

if [ "$1" = 'test' ]; then
    exec nedge -h
else
    # can use this to run nedge in the background for example
    exec "$@"    
fi
