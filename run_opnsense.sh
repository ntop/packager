#!/usr/bin/env bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""

#############

# Import alert-related functions
source ./utils/alerts.sh

#############

function usage {
    echo "Usage: run_opnsense.sh [--cleanup] | [ -f=<mail from> -t=<mail to> ]"
    echo ""
    echo "-c|--cleanup "
    echo "-f|--mail-from=<email from>"
    echo "-t|--mail-to=<email to>"
    echo "-d|--discord-webhook=<discord webhook>"
    echo "-h|--help"
    echo ""
    echo "This tool will test FreeBSD images on OPNsense"
    exit 0
}

#############

function cleanup {
    pkg remove -y ntop ntopng nprobe
}

#############

function test_installation {
    # $1 is the ntop package URL, e.g., "https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz"

    # Install dependencies
    pkg install -y bash
    pkg install -y ca_root_nss # Otherwise it will fail with Certificate verification failed

    # Update the distro.
    pkg upgrade -y

    # Remove old files
    pkg remove -y ntop ntopng nprobe redis

    # Install the ntop repo
    # e.g. https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz
    pkg add $1

    # Install the packages
    pkg install -y redis
    pkg install -y ntopng
    pkg install -y nprobe

    # Enable the services
    sysrc redis_enable="YES"
    #sysrc ntopng_enable="YES"
    #sysrc nprobe_enable="YES"

    # Start redis
    service redis start

    # Test the products
    /usr/local/bin/bash -c "ntopng --version"
    if /usr/local/bin/bash -c "ntopng -h"; then
	sendSuccess "OPNsense ntopng package TEST completed successfully" "All tests run correctly."
    else
	sendError "OPNsense ntopng package TEST failed" "Unable to TEST ntopng package"
    fi

    /usr/local/bin/bash -c "nprobe --version"
    if /usr/local/bin/bash -c "nprobe -h"; then
	sendSuccess "OPNsense nprobe package TEST completed successfully" "All tests run correctly."
    else
	sendError "OPNsense nprobe package TEST failed" "Unable to TEST nprobe package"
    fi
}

#############

for i in "$@"
do
    case $i in
	-c|--cleanup)
	    cleanup
	    exit 0
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

test_installation "https://packages.ntop.org/FreeBSD/FreeBSD:13:amd64/latest/ntop-1.0.pkg"

