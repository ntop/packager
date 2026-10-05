#!/usr/bin/env bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""
TAG="dev"

#############

OUT="out"
/bin/rm -rf ${OUT}
mkdir -p ${OUT}

#############

# Import alert-related functions
source ./utils/alerts.sh

#############

function usage {
    echo "Usage: run_freebsd.sh [--bootstrap] | [--cleanup] | [-m=stable] [ -f=<mail from> -t=<mail to> ]"
    echo ""
    echo "-m|--mode=<branch> [dev (default), stable: the version check is run on dev packages only]"
    echo "-b|--bootstrap [run this manually as requires interactive mode]"
    echo "-c|--cleanup "
    echo "-f|--mail-from=<email from>"
    echo "-t|--mail-to=<email to>"
    echo "-d|--discord-webhook=<discord webhook>"
    echo "-h|--help"
    echo ""
    echo "This tool will test FreeBSD images"
    exit 0
}

#############

function cleanup {
    # $1 is the jail name, .e.g, "freebsd11_4"

    # Stop all jails
    service jail onestop $1

    ## Remove all jail files
    if [ -d /jail/$1 ]; then
        umount /jail/$1/dev
	chflags -R noschg /jail/$1
	rm -rf /jail/$1
    fi
}

#############

function bootstrap_release {
    # $1 is the jail name, .e.g, "freebsd11_4"
    # $2 is the release name, e.g., "11.4-RELEASE"

    ## Inspired by https://rderik.com/blog/running-a-web-server-on-freebsd-inside-a-jail/

    ## JAILS initialization

    export DISTRIBUTIONS="base.txz"
    export BSDINSTALL_DISTDIR="/jail/$1/"
    export BSDINSTALL_DISTSITE="https://download.freebsd.org/ftp/releases/amd64/$2/"

    # Create the base jail directory
    mkdir -p /jail/$1

    # Fetch the base system (uses the export-ed environment variables above)
    bsdinstall distfetch

    # Extract the base system
    cd ${BSDINSTALL_DISTDIR}
    tar -xvpf base.txz

    # Add the resolv.conf for name resolution
    cp /etc/resolv.conf /jail/$1/etc/
}

#############

function bootstrap_jails {
    # Stop all jails
    service jail onestop

    cat <<EOF > /etc/jail.conf
# 1. definition of variables that we'll use through the config file
\$jail_path="/jail";
path="\$jail_path/\$name";

# 2. begin - default configuration for all jails

# 3. Some applications might need access to devfs
mount.devfs;

# 4. Clear environment variables
exec.clean;

# 5. Use the host's network stack for all jails
ip4=inherit;
ip6=inherit;

# 6. Initialisation scripts
exec.start="sh /etc/rc";
exec.stop="sh /etc/rc.shutdown";

# 7. specific jail configuration
freebsd14_4 {}
freebsd15_1 {}
EOF
}

#############

function check_product {
    # $1 is the jail name, .e.g, "freebsd11_4"
    # $2 is the release name, e.g., "11.4-RELEASE"
    # $3 is the product name, e.g., "ntopng"

    # Functional test
    jexec $1 /usr/local/bin/bash -c "$3 --version"
    if jexec $1 /usr/local/bin/bash -c "$3 -h"; then
	sendSuccess "FreeBSD $2 $3 package TEST completed successfully" "All tests run correctly."
    else
	LOG_FILE="${OUT}/$3-${1}.log"
	jexec $1 /usr/local/bin/bash -c "$3 -h" &> "${LOG_FILE}"
	sendError "FreeBSD $2 $3 package TEST failed" "Unable to TEST $3 package" "${LOG_FILE}" "2"
	return
    fi

    # Version check (dev packages only): the version string should contain today's date (YYMMDD)
    if [ "$TAG" = "dev" ]; then
	TODAY=$(date +%y%m%d)
	LOG_FILE="${OUT}/$3-${1}_version.log"
	jexec $1 /usr/local/bin/bash -c "$3 --version" &> "${LOG_FILE}"
	if grep -q "Version:.*\.${TODAY}" "${LOG_FILE}"; then
	    sendSuccess "FreeBSD $2 $3 package VERSION CHECK completed successfully" "Version string contains ${TODAY}."
	else
	    echo "Version check FAILED: expected date ${TODAY} in version string" >> "${LOG_FILE}"
	    sendError "FreeBSD $2 $3 package VERSION CHECK failed" "" "${LOG_FILE}" "2"
	fi
    fi

    # License check: copy the host license file into the jail (skipped when no license file is found on the host)
    LICENSE_FILE="/usr/local/etc/$3.license"
    if [ -f "${LICENSE_FILE}" ]; then
	cp "${LICENSE_FILE}" "/jail/$1${LICENSE_FILE}"
	LOG_FILE="${OUT}/$3-${1}_license.log"
	jexec $1 /usr/local/bin/bash -c "$3 --version" &> "${LOG_FILE}"
	if grep -qi "Invalid license\|License Type:.*Invalid" "${LOG_FILE}"; then
	    echo "License check FAILED: invalid license detected" >> "${LOG_FILE}"
	    sendError "FreeBSD $2 $3 package LICENSE CHECK failed" "" "${LOG_FILE}" "2"
	elif ! grep -q "License Type:\|Edition:" "${LOG_FILE}"; then
	    echo "License check FAILED: no license type reported" >> "${LOG_FILE}"
	    sendError "FreeBSD $2 $3 package LICENSE CHECK failed" "" "${LOG_FILE}" "2"
	else
	    sendSuccess "FreeBSD $2 $3 package LICENSE CHECK completed successfully" "Valid license reported."
	fi
    else
	echo "No license file ${LICENSE_FILE} found on the host, skipping $3 license check"
    fi

    # PCAP test: run with a pcap file and check the exit status (uses the same license of the license test)
    PCAP_URL="https://raw.githubusercontent.com/ntop/ntopng-e2e-tests/dev/rest/pcap/web_attack_01.pcap"
    PCAP_FILE="/tmp/pcap-test.pcap"
    LOG_FILE="${OUT}/$3-${1}_pcap.log"
    case "$3" in
	ntopng)
	    PCAP_CMD="mkdir -p /tmp/ntopng-pcap-test && ntopng -i ${PCAP_FILE} --shutdown-when-done -d /tmp/ntopng-pcap-test -w 0"
	    ;;
	nprobe)
	    PCAP_CMD="nprobe -i ${PCAP_FILE} -n none"
	    ;;
	*)
	    PCAP_CMD=""
	    ;;
    esac
    if [ -n "${PCAP_CMD}" ]; then
	if ! fetch -q -o "/jail/$1${PCAP_FILE}" "${PCAP_URL}" &> "${LOG_FILE}"; then
	    echo "Failed to download pcap file ${PCAP_URL}" >> "${LOG_FILE}"
	    sendError "FreeBSD $2 $3 package PCAP TEST failed" "" "${LOG_FILE}" "2"
	elif jexec $1 /usr/local/bin/bash -c "${PCAP_CMD}" &> "${LOG_FILE}"; then
	    sendSuccess "FreeBSD $2 $3 package PCAP TEST completed successfully" "Test pcap file processed correctly."
	else
	    if [[ ! -s "${LOG_FILE}" ]]; then
		echo "No log output during the PCAP TEST phase" > "${LOG_FILE}"
	    fi
	    sendError "FreeBSD $2 $3 package PCAP TEST failed" "" "${LOG_FILE}" "2"
	fi
	rm -rf "/jail/$1${PCAP_FILE}" "/jail/$1/tmp/ntopng-pcap-test"
    fi

    rm -f "/jail/$1${LICENSE_FILE}"
}

#############

function test_jail {
    # $1 is the jail name, .e.g, "freebsd11_4"
    # $2 is the release name, e.g., "11.4-RELEASE"
    # $3 is the ntop package URL, e.g., "https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz"

    # Start the jail
    service jail onestart $1

    # Install dependencies
    pkg -j $1 install -y bash
    pkg -j $1 install -y ca_root_nss # Otherwise it will fail with Certificate verification failed
    pkg -j $1 install -y pkg

    # Update the distro. PAGER is used to avoid interactive mode
    # Jail and release name are passed as well
    # e.g., env PAGER=cat freebsd-update --currently-running 11.4-RELEASE -b /jail/freebsd11_4 fetch install
    env PAGER=cat freebsd-update --currently-running $2 -b /jail/$1 fetch install
    pkg -j $1 upgrade -y

    # Remove old files
    pkg -j $1 remove -y ntop ntopng nprobe redis

    # Install the ntop repo
    #e.g., https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz
    if ! pkg -j $1 add $3; then
	sendError "FreeBSD $2 ntop repository ADD failed" "Unable to add the ntop pkg repository from $3 (repo bootstrap package missing or unreachable upstream). Skipping package tests for this release." "" "2"
	service jail onestop $1
	return 1
    fi

    jexec $1 /bin/freebsd-version

    # Install the packages
    pkg -j $1 install -y redis

    # Enable the services
    sysrc -j $1 redis_enable="YES"

    # Start jailed redis
    jexec $1 service redis start

    if pkg -j $1 install -y ntopng; then
	sysrc -j $1 ntopng_enable="YES"
	check_product $1 $2 ntopng
    else
	sendError "FreeBSD $2 ntopng package INSTALL failed" "pkg install ntopng failed: package not available in the ntop repository for this release" "" "2"
    fi

    if pkg -j $1 install -y nprobe; then
	sysrc -j $1 nprobe_enable="YES"
	check_product $1 $2 nprobe
    else
	sendError "FreeBSD $2 nprobe package INSTALL failed" "pkg install nprobe failed: package not available in the ntop repository for this release" "" "2"
    fi

    # Cleanup cached packages
    pkg -j $1 autoremove -y
    pkg -j $1 clean -a -y

    # Done, stop the jail
    service jail onestop $1
}

#############

for i in "$@"
do
    case $i in
	-b|--bootstrap)
	    #cleanup "freebsd12_4"
	    #cleanup "freebsd13_5"
	    cleanup "freebsd14_4"
	    cleanup "freebsd15_1"
	    #bootstrap_release "freebsd12_4" "12.4-RELEASE"
	    #bootstrap_release "freebsd13_5" "13.3-RELEASE"
	    bootstrap_release "freebsd14_4" "14.4-RELEASE"
	    bootstrap_release "freebsd15_1" "15.1-RELEASE"
	    bootstrap_jails
	    exit 0
	    ;;

	-c|--cleanup)
	    #cleanup "freebsd12_4"
	    #cleanup "freebsd13_5"
	    cleanup "freebsd14_4"
	    cleanup "freebsd15_1"
	    exit 0
	    ;;

	-m=*|--mode=*)
	    if [ "${i#*=}" == "stable" ]; then
		TAG="stable"
	    fi
	    ;;

	-f=*|--mail-from=*)
	    MAIL_FROM="${i#*=}"
	    ;;

	-t=*|--mail-to=*)
	    MAIL_TO="${i#*=}"
	    ;;

	-d=*|--discord-webhook=*)
	    DISCORD_WEBHOOK="${i#*=}"
	    ;;

	-h|--help)
	    usage
	    exit 0
	    ;;

	*)
	    # unknown option
	    ;;
    esac
done

# if [ -z "$MAIL_FROM" ] || [ -z "$MAIL_TO" ] ; then
#    echo "Warning: please specify -f=<from> -t=<to> to send alerts by mail"
# fi

# if [ -z "$DISCORD_WEBHOOK" ] ; then
#    echo "Warning: please specify -d=<discord webhook url> to send alerts to Discord"
# fi

#test_jail "freebsd12_4" "12.4-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:12:amd64/latest/ntop-1.0.txz"
#test_jail "freebsd13_5" "13.5-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:13:amd64/latest/ntop-1.0.pkg"
test_jail "freebsd14_4" "14.4-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:14:amd64/latest/ntop-1.0.pkg"
test_jail "freebsd15_1" "15.1-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:15:amd64/latest/ntop-1.0.pkg"

