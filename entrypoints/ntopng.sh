#!/bin/bash

# specify here the packages you want to install before running this script
# TEST_PACKAGES: ntopng

set -e

REDIS_SOCK="/tmp/redis.sock"

# Start a private redis instance listening on a Unix socket to avoid collision
# on port 6379 with other containers using --net=host
start_redis() {
    redis-server --unixsocket "$REDIS_SOCK" --port 0 --daemonize yes
    for i in $(seq 1 50); do
        [ -S "$REDIS_SOCK" ] && return 0
        sleep 0.1
    done
    echo "Redis socket $REDIS_SOCK not available"
    exit 1
}

# Pick a random port not currently in use by other ntopng instances to avoid
# collisions when running multiple tests in parallel with --net=host
pick_http_port() {
    local port hex
    for i in $(seq 1 100); do
        port=$((10000 + RANDOM % 20000))
        hex=$(printf ':%04X ' $port)
        if ! grep -qi "$hex" /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
            echo $port
            return 0
        fi
    done
    echo "Unable to find a free TCP port" >&2
    return 1
}

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
elif [ "$1" = 'license-mgr-check' ]; then
    LICENSE_MGR_CONF="/usr/share/ntop/etc/license-manager-client-ntopng.conf"
    VERSION_OUTPUT=$(ntopng --license-mgr "$LICENSE_MGR_CONF" --version 2>&1)
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
    ntopng --version
elif [ "$1" = 'pcap-test' ]; then
    PCAP_URL="https://raw.githubusercontent.com/ntop/ntopng-e2e-tests/dev/rest/pcap/web_attack_01.pcap"
    PCAP_FILE="/tmp/pcap-test.pcap"
    wget -q "$PCAP_URL" -O "$PCAP_FILE" || { echo "Failed to download pcap file"; exit 1; }
    start_redis
    HTTP_PORT=$(pick_http_port)
    mkdir -p /tmp/ntopng-pcap-test
    exec ntopng -r "$REDIS_SOCK" -i "$PCAP_FILE" --shutdown-when-done -d /tmp/ntopng-pcap-test -w ":$HTTP_PORT"
elif [ "$1" = 'pcap-test-license-mgr' ]; then
    PCAP_URL="https://raw.githubusercontent.com/ntop/ntopng-e2e-tests/dev/rest/pcap/web_attack_01.pcap"
    PCAP_FILE="/tmp/pcap-test.pcap"
    wget -q "$PCAP_URL" -O "$PCAP_FILE" || { echo "Failed to download pcap file"; exit 1; }
    LICENSE_MGR_CONF="/usr/share/ntop/etc/license-manager-client-ntopng.conf"
    start_redis
    HTTP_PORT=$(pick_http_port)
    mkdir -p /tmp/ntopng-pcap-test
    exec ntopng --license-mgr "$LICENSE_MGR_CONF" -r "$REDIS_SOCK" -i "$PCAP_FILE" --shutdown-when-done -d /tmp/ntopng-pcap-test -w ":$HTTP_PORT"
else
    # can use this to run ntopng in the background for example
    exec "$@"
fi
