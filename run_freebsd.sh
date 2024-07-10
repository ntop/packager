#!/usr/bin/env bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""

#############

OUT="out"
/bin/rm -rf ${OUT}
mkdir -p ${OUT}

#############

# Import alert-related functions
source ./utils/alerts.sh

#############

function usage {
    echo "Usage: run_freebsd.sh [--bootstrap] | [--cleanup] | [ -f=<mail from> -t=<mail to> ]"
    echo ""
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
freebsd13_3 {}
freebsd14_1 {}
EOF
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
    pkg -j $1 add $3

    jexec $1 /bin/freebsd-version

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
	LOG_FILE="${OUT}/ntopng-${1}.log"
        jexec $1 /usr/local/bin/bash -c "ntopng -h" &> "${LOG_FILE}"
	sendError "FreeBSD $2 ntopng package TEST failed" "Unable to TEST ntopng package" "${LOG_FILE}" "2"
    fi

    jexec $1 /usr/local/bin/bash -c "nprobe --version"
    if jexec $1 /usr/local/bin/bash -c "nprobe -h"; then
	sendSuccess "FreeBSD $2 nprobe package TEST completed successfully" "All tests run correctly."
    else
	LOG_FILE="${OUT}/nprobe-${1}.log"
        jexec $1 /usr/local/bin/bash -c "nprobe -h" &> "${LOG_FILE}"
	sendError "FreeBSD $2 nprobe package TEST failed" "Unable to TEST nprobe package" "$LOG_FILE" "2"
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
	    cleanup "freebsd13_3"
	    cleanup "freebsd14_1"
	    #bootstrap_release "freebsd12_4" "12.4-RELEASE"
	    bootstrap_release "freebsd13_3" "13.3-RELEASE"
	    bootstrap_release "freebsd14_1" "14.1-RELEASE"
	    bootstrap_jails
	    exit 0
	    ;;

	-c|--cleanup)
	    #cleanup "freebsd12_4"
	    cleanup "freebsd13_3"
	    cleanup "freebsd14.1"
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

#test_jail "freebsd12_4" "12.4-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:12:amd64/latest/ntop-1.0.txz"
test_jail "freebsd13_3" "13.3-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:13:amd64/latest/ntop-1.0.pkg"
test_jail "freebsd14_1" "14.1-RELEASE" "https://packages.ntop.org/FreeBSD/FreeBSD:14:amd64/latest/ntop-1.0.pkg"

