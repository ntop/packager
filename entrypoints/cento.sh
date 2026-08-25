#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: cento

set -e

if [ "$1" = 'test' ]; then
    cento-ids -h
    exec cento     -h
elif [ "$1" = 'version-check' ]; then
    TODAY=$(date +%y%m%d)
    VERSION_OUTPUT=$(cento --version 2>&1)
    echo "$VERSION_OUTPUT"
    if ! echo "$VERSION_OUTPUT" | grep -q "Version:.*\.$TODAY"; then
        echo "Version check FAILED: expected date $TODAY in version string"
        exit 1
    fi
elif [ "$1" = 'license-check' ]; then
    VERSION_OUTPUT=$(cento --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:\|Edition:"; then
        echo "License check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'license-mgr-check' ]; then
    LICENSE_MGR_CONF="/usr/share/ntop/etc/license-manager-client-cento.conf"
    VERSION_OUTPUT=$(cento --license-mgr "$LICENSE_MGR_CONF" --version 2>&1)
    echo "$VERSION_OUTPUT"
    if echo "$VERSION_OUTPUT" | grep -qi "Invalid license\|License Type:.*Invalid"; then
        echo "License manager check FAILED: invalid license detected"
        exit 1
    fi
    if ! echo "$VERSION_OUTPUT" | grep -q "License Type:\|Edition:"; then
        echo "License manager check FAILED: no license type reported"
        exit 1
    fi
elif [ "$1" = 'print-version' ]; then
    cento --version
elif [ "$1" = 'pcap-test' ]; then
    PCAP_URL="https://raw.githubusercontent.com/ntop/ntopng-e2e-tests/dev/rest/pcap/web_attack_01.pcap"
    PCAP_FILE="/tmp/pcap-test.pcap"
    wget -q "$PCAP_URL" -O "$PCAP_FILE" || { echo "Failed to download pcap file"; exit 1; }
    exec cento -i "$PCAP_FILE"
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
