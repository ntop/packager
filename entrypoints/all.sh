#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: pfring n2disk cento nprobe ntopng nscrub ntap
# NOTE: we do not install nbox as it's not available on all platforms

set -e

if [ "$1" = 'test' ]; then
    # do interesting test stuff here
    echo "<test to be decided>"
elif [ "$1" = 'version-check' ]; then
    # all.sh installs multiple packages; version checks are done per-package entrypoint
    exit 0
elif [ "$1" = 'license-check' ]; then
    # all.sh installs multiple packages, license checks are done per-package entrypoint
    exit 0
elif [ "$1" = 'print-version' ]; then
    # all.sh installs multiple packages, printing one of them (ntopng), use the exact image to print the required version
    ntopng --version || true
elif [ "$1" = 'pcap-test' ]; then
    # pcap tests are executed on per-package entrypoints only
    exit 0
else
    # can use this to run the software in the background for example
    exec "$@"
fi
