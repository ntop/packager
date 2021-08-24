#!/bin/bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""
RELEASE=""  # e.g., centos7, debianbuster, ubuntu20
PACKAGE="" # e.g., cento, n2disk, nprobe, ntopng, pfring

# Import functions to send out alerts
source utils/alerts.sh

function usage {
    echo "Usage: run.sh [--cleanup] | [ [-m=stable] -f=<mail from> -t=<mail to> -d=<discord webhook> -r=<release> -p=<package>]"
    echo ""
    echo "-r|----release   : Builds for a specific release. Optional, all releases are built when not specified."
    echo "                   Available releases: centos7, debianbuster, debianjessie, debianstretch, debianbullseye, ubuntu16, ubuntu18, ubuntu20."
    echo "-p|--package     : Builds a specific package. Optional, all packages are built when not specified."
    echo "                   Available packages: cento, n2disk, nprobe, ntopng, pfring."
    echo "-c|--cleanup     : clears all docker images and containers"
    echo ""
    echo "This tool will build some empty docker containers where ntop packages"
    echo "will be installed. This tool will make some tests and report"
    echo "results via email, thus it is necessary to set -f and -t."
    exit 0
}

function cleanup {
    \rm -f *~ &> /dev/null

    CONT=$(${DOCKER} ps -a -q | xargs)
    if [[ $CONT ]]; then
	echo "Cleaning up containers: ${CONT}"
	${DOCKER} rm -f ${CONT}
    fi

    # clean only the images that are prefixed with TAG
    #IMGS=$(${DOCKER} images -q --filter "dangling=true" | xargs)
    IMGS=$(${DOCKER} images -q | xargs)
    if [[ $IMGS ]]; then
	echo "Cleaning up images: ${IMGS}"
	${DOCKER} rmi -f ${IMGS}
    fi
}

DOCKER="sudo docker"
TAG="development"
STABLE_SUFFIX=""

#############

for i in "$@"
do
    case $i in
	-m=*|--mode=*)
	    if [ "${i#*=}" == "stable" ]; then
		STABLE_SUFFIX="-stable"
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

	-r=*|--release=*)
	    RELEASE="${i#*=}"
	    ;;

	-p=*|--package=*)
	    PACKAGE="${i#*=}"
	    ;;

	-c|--cleanup)
	    cleanup
	    exit 0
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

if [ -z "$MAIL_FROM" ] || [ -z "$MAIL_TO" ] ; then
    echo "Warning: please specify -f=<from> -t=<to> to send alerts by mail"
fi

if [ -z "$DISCORD_WEBHOOK" ] ; then
    echo "Warning: please specify -d=<discord webhook url> to send alerts to Discord"
fi

OUT="out-${TAG}"
/bin/rm -rf ${OUT}
mkdir -p ${OUT}/generic

WHEEZY_BACKPORTS="RUN grep -q 'wheezy-backports' /etc/apt/sources.list || echo 'deb http\\://ftp.debian.org/debian wheezy-backports main' >> /etc/apt/sources.list"
JESSIE_BACKPORTS="RUN echo 'deb http\\://archive.debian.org/debian jessie-backports main' >> /etc/apt/sources.list \\&\\& echo 'Acquire\\:\\:Check-Valid-Until no;' > /etc/apt/apt.conf.d/99no-check-valid-until \\&\\& apt-get update \\&\\& apt-get install libjson-c2"
# Debian buster and stretch need to have 'contrib' in sources.list for package geoipupdate
APT_SOURCES_LIST="RUN sed -i 's/main/main contrib/g' /etc/apt/sources.list" #"sed -i 's/main/main contrib/g' /etc/apt/sources.list"
# UBUNTU14_PPA="RUN apt-get -y install software-properties-common \\&\\& add-apt-repository ppa\\:maxmind/ppa \\&\\& apt-get update"
UBUNTU18_REPOSITORIES="RUN apt-get update \\&\\& apt-get -y -q install gnupg software-properties-common \\&\\& add-apt-repository universe"

SALTSTACK="RUN wget https\\://copr.fedoraproject.org/coprs/saltstack/zeromq4/repo/epel-6/saltstack-zeromq4-epel-6.repo \&\& mv saltstack-zeromq4-epel-6.repo /etc/yum.repos.d/ "

# Producing Dockerfile(s)

# sed -e "s:VERSION:12.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:REPOSITORIES::g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu12
# sed -e "s:VERSION:14.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS:${UBUNTU14_PPA}:g" -e "s:REPOSITORIES::g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu14
sed -e "s:VERSION:16.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:REPOSITORIES::g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu16
sed -e "s:VERSION:18.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:REPOSITORIES:${UBUNTU18_REPOSITORIES}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu18
sed -e "s:VERSION:20.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:REPOSITORIES:${UBUNTU18_REPOSITORIES}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu20

#sed -e "s:VERSION:wheezy:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS:${WHEEZY_BACKPORTS}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianwheezy
sed -e "s:VERSION:jessie:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS:${JESSIE_BACKPORTS}:g" -e "s:APT_SOURCES_LIST::g" docker/Dockerfile.debianjessie.seed > ${OUT}/generic/Dockerfile.debianjessie
sed -e "s:VERSION:stretch:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:APT_SOURCES_LIST:${APT_SOURCES_LIST}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianstretch
sed -e "s:VERSION:buster:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:APT_SOURCES_LIST:${APT_SOURCES_LIST}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbuster
sed -e "s:VERSION:bullseye:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" -e "s:APT_SOURCES_LIST:${APT_SOURCES_LIST}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbullseye

# Raspbian
#sed -e "s:VERSION:stretch:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.raspbian.seed > ${OUT}/generic/Dockerfile.raspbianstretch

# Centos7
sed -e "s:MINOR:7.6.1810:g" -e "s:CENTOS8:#:g" -e "s:MAJOR:7:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK::g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos7
# Centos8
sed -e "s:MINOR:8:g" -e "s:CENTOS8::g" -e "s:MAJOR:8:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK::g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos8

INSTALLATION_FAILURES=0
INSTALLATION_FAILED_IMAGES=""

FUNCTIONAL_FAILURES=0
FUNCTIONAL_FAILED_IMAGES=""

IMAGES=""

# Cleanup all containers/images
cleanup

# ########################################################################################################################
# Build and test docker images for each supported distro and for each softare product so to test everything independently
# ########################################################################################################################

for DOCKERFILE_GENERIC in ${OUT}/generic/Dockerfile.*; do
    DOCKERFILE_RELEASE="${DOCKERFILE_GENERIC##*.}"

    for ENTRYPOINT in entrypoints/*.sh; do
        ENTRYPOINT_SH=`basename ${ENTRYPOINT}`
        PACKAGES_LIST=`cat $ENTRYPOINT | grep TEST_PACKAGES | cut -d ':' -f 2 | xargs`

	IMG="${DOCKERFILE_RELEASE}.${TAG}.${PACKAGES_LIST// /.}"
	DOCKERFILE=${OUT}/Dockerfile.${IMG}

        # #################################################################################################################
        # INSTALLATION TEST
        # #################################################################################################################

	if [ "centos8.development.n2disk" == ${IMG} ] || [ "centos8.stable.n2disk" == ${IMG} ]; then
	    # Seems n2disk on centos8 attempts to install kernel-related stuff which is not supported on docker
	    continue
	fi

	if [[ ${IMG} == centos8.* ]]; then
	    # Seems centos8 has the rpmdb broken on docker
	    # https://github.com/ansible/awx/issues/6306
	    # must skip until this is solved
	    continue
	fi

	if [ "$IMG" = "seed" ]; then
	    continue
	fi

	if [ ! -z "${RELEASE}" ]; then
	    if [ "x${RELEASE}" != "x${DOCKERFILE_RELEASE}" ]; then
		# A specific release has been requested, skip releases that are not matching
		continue
	    fi
	fi

	if [ ! -z "${PACKAGE}" ]; then
	    if [ "x${PACKAGE}" != "x${PACKAGES_LIST}" ]; then
		# A specific package has been requested, skip releases that are not matching
		continue
	    fi
	fi

	echo "Preparing docker image ${IMG} [packages: $PACKAGES_LIST] [entrypoint: $ENTRYPOINT]"

	sed -e "s:PACKAGES_LIST:${PACKAGES_LIST}:g" \
	    -e "s:ENTRYPOINT_PATH:${ENTRYPOINT}:g" \
	    -e "s:ENTRYPOINT_SH:${ENTRYPOINT_SH}:g" \
	    ${DOCKERFILE_GENERIC} > ${DOCKERFILE}

	MAX_ATTEMPTS=2
	attempt=1
	while [ $attempt -le $MAX_ATTEMPTS ]
	do
	    echo "Running ${DOCKER} build --no-cache -t ${IMG} -f ${DOCKERFILE} ."

	    ${DOCKER} build --no-cache -t ${IMG} -f ${DOCKERFILE} . &> ${OUT}/${IMG}${STABLE_SUFFIX}.log

	    if [ $? == 0 ]; then break; fi

	    let attempt=attempt+1
	    echo -e "Attempt #$attempt.."
	done

	if [ "$attempt" -gt "$MAX_ATTEMPTS" ];
	then
	    echo "Failed ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . &> ${OUT}/${IMG}${STABLE_SUFFIX}.log"
	    echo "Failure, see ${OUT}/${IMG}${STABLE_SUFFIX}.log for more details"
	    let INSTALLATION_FAILURES=INSTALLATION_FAILURES+1
	    INSTALLATION_FAILED_IMAGES="${IMG} ${INSTALLATION_FAILED_IMAGES}"
	    # Sending mail with log
	    if [[ ! -s ${OUT}/${IMG}${STABLE_SUFFIX}.log ]]; then
	        echo "No log output during the BUILD phase" >  "${OUT}/${IMG}${STABLE_SUFFIX}.log"
	    fi
	    sendError "Packages INSTALLATION failed on ${IMG} ${TAG}" "" "${OUT}/${IMG}${STABLE_SUFFIX}.log"
	else
	    IMAGES="${IMAGES} ${IMG}"

            # #################################################################################################################
            # FUNCTIONAL TESTS
            # #################################################################################################################

	    echo -n "Testing ${IMG}... "
	    ${DOCKER} run ${IMG} test &> ${OUT}/${IMG}${STABLE_SUFFIX}_test.log
	    if [ $? != 0 ]; then
	        echo "FAIL Failed to execute: ${DOCKER} run ${IMG} test [see ${OUT}/${IMG}${STABLE_SUFFIX}_test.log for more details]"
	        let FUNCTIONAL_FAILURES=FUNCTIONAL_FAILURES+1
	        FUNCTIONAL_FAILED_IMAGES="${IMG} ${FUNCTIONAL_FAILED_IMAGES}"
	        # Sending mail with log
	        if [[ ! -s  ${OUT}/${IMG}${STABLE_SUFFIX}_test.log ]]; then
	            echo "No log output during the TEST phase" > "${OUT}/${IMG}${STABLE_SUFFIX}_test.log"
	        fi
                sendError "Packages TEST failed for ${IMG} ${TAG}" "" "${OUT}/${IMG}${STABLE_SUFFIX}_test.log"
	    else
	        echo "OK"
	    fi

	fi
    done

    # Cleaning up created images/containers to make room on disk
    cleanup

done

if [ "$INSTALLATION_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages INSTALLATION failed on $INSTALLATION_FAILURES images" "Unable to build docker images: ${INSTALLATION_FAILED_IMAGES}"
else
    sendSuccess "${TAG} packages INSTALLATION completed successfully" "All docker images built correctly."
fi

if [ "$FUNCTIONAL_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages TEST failed on $FUNCTIONAL_FAILURES images" "Unable to TEST docker images: ${FUNCTIONAL_FAILED_IMAGES}"
else
    sendSuccess "${TAG} packages TEST completed successfully" "All docker images test correctly."
fi

