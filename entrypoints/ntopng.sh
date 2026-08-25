#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: ntopng

set -e

if [ "$1" = 'test' ]; then
    exec ntopng -h
elif [ "$1" = 'version-check' ]; then
    TODAY=$(date +%y%m%d)
    VERSION_OUTPUT=$(ntopng --version 2>&1)
    echo "$VERSION_OUTPUT"
    if ! echo "$VERSION_OUTPUT" | grep -q "Version:.*\.$TODAY"; then
        echo "Version check FAILED: expected date $TODAY in version string"
        exit 1
    fi
elif [ "$1" = 'license-check' ]; then
    VERSION_OUTPUT=$(ntopng --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:\|Edition:"; then
        echo "License check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'print-version' ]; then
    ntopng --version
elif [ "$1" = 'pcap-test' ]; then
    PCAP_URL="https://raw.githubusercontent.com/ntop/ntopng-e2e-tests/dev/rest/pcap/web_attack_01.pcap"
    PCAP_FILE="/tmp/pcap-test.pcap"
    wget -q "$PCAP_URL" -O "$PCAP_FILE" || { echo "Failed to download pcap file"; exit 1; }
    redis-server --daemonize yes
    mkdir -p /tmp/ntopng-pcap-test
    exec ntopng -i "$PCAP_FILE" --shutdown-when-done -d /tmp/ntopng-pcap-test -w 0
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
