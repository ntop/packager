#!/usr/bin/env bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""

#############

# Import alert-related functions
source ./utils/alerts.sh

#############

function usage {
    echo "Usage: run.sh [--bootstrap] | [--cleanup] | [ -f=<mail from> -t=<mail to> ]"
    echo ""
    echo "-c|--cleanup "
    echo ""
    echo "This tool will test FreeBSD images"
    exit 0
}

#############

function cleanup {
    # $1 is the jail name, .e.g, "freebsd11_4"

    # Stop all jails
    service jail stop $1

    ## Remove all jail files
    if [ -d /jail/$1 ]; then
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
    service jail stop

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
freebsd11_4 {}
freebsd12_2 {}
EOF
}

#############

function test_jail {
    # $1 is the jail name, .e.g, "freebsd11_4"
    # $2 is the release name, e.g., "11.4-RELEASE"
    # $3 is the ntop package URL, e.g., "https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz"

    # Start the jail
    service jail start $1

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
    pkg -j $1 add $3

    # Install the packages
    pkg -j $1 install -y redis
    pkg -j $1 install -y ntopng
    pkg -j $1 install -y nprobe

    # Enable the services
    sysrc -j $1 redis_enable="YES"
    sysrc -j $1 ntopng_enable="YES"
    sysrc -j $1 nprobe_enable="YES"

    # Start jailed redis
    jexec $1 service redis start

    # Test the products
    jexec $1 /usr/local/bin/bash -c "ntopng --version"
    if jexec $1 /usr/local/bin/bash -c "ntopng -h"; then
	sendSuccess "FreeBSD $2 ntopng package TEST completed successfully" "All tests run correctly."
    else
	sendError "FreeBSD $2 ntopng package TEST failed" "Unable to TEST ntopng package"
    fi

    jexec $1 /usr/local/bin/bash -c "nprobe --version"
    if jexec $1 /usr/local/bin/bash -c "nprobe -h"; then
	sendSuccess "FreeBSD $2 nprobe package TEST completed successfully" "All tests run correctly."
    else
	sendError "FreeBSD $2 nprobe package TEST failed" "Unable to TEST nprobe package"
    fi

    # Done, stop the jail
    service jail stop $1
}

#############

for i in "$@"
do
    case $i in
	-b|--bootstrap)
	    cleanup
	    bootstrap_release "freebsd11_4" "11.4-RELEASE"
	    bootstrap_release "freebsd12_2" "12.2-RELEASE"
	    bootstrap_jails
	    exit 0
	    ;;

	-c|--cleanup)
	    cleanup "freebsd11_4"
	    cleanup "freebsd12_2"
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

# sendSuccess "packages INSTALLATION completed successfully" "" "/etc/passwd"
# sendError "${TAG} packages TEST failed on $FUNCTIONAL_FAILURES images" "Unable to TEST docker images: ${FUNCTIONAL_FAILED_IMAGES}"

test_jail "freebsd11_4" "11.4-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:11:amd64/latest/ntop-1.0.txz"
test_jail "freebsd12_2" "12.2-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:12:amd64/latest/ntop-1.0.txz"
