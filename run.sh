#!/bin/bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""
RELEASE=""  # e.g., centos7, rockylinux8, rockylinux9, debianbuster, debianbullseye, debianbookworm, ubuntu18, ubuntu20, ubuntu22
PACKAGE="" # e.g., cento, n2disk, nprobe, ntopng, nedge, nscrub, ntap, pfring

DOCKER="sudo docker"
TAG="development"
STABLE_SUFFIX=""

# Import functions to send out alerts
source utils/alerts.sh

function usage {
    echo "Usage: run.sh [--cleanup] | [-m=stable] [-f=<mail from>] [-t=<mail to>] [-d=<discord webhook>] [-r=<release>] [-p=<package>]"
    echo ""
    echo "-m=<branch>                : Select branch."
    echo "                             Available branches: (default: dev), stable."
    echo "-r|--release=<release>     : Builds for a specific release. Optional, all releases are built when not specified."
    echo "                             Available releases: centos7, rockylinux8, rockylinux9, debianbuster (10), debianbullseye (11), debianbookworm (12), ubuntu18, ubuntu20, ubuntu22."
    echo "-p|--package=<package>     : Builds a specific package. Optional, all packages are built when not specified."
    echo "                             Available packages: cento, n2disk, nprobe, ntopng, nedge, nscrub, ntap, pfring."
    echo "-c|--cleanup               : clears all docker images and containers"
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

    #IMGS=$(${DOCKER} images -q --filter "dangling=true" | xargs)
    IMGS=$(${DOCKER} images -q | xargs)
    if [[ $IMGS ]]; then
        echo "Cleaning up images: ${IMGS}"
        ${DOCKER} rmi -f ${IMGS}
    fi

    # Purge /var/lib/docker/overlay2/
    ${DOCKER} system prune -a -f
}

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

# Producing Dockerfile(s)

# Ubuntu
sed -e "s:VERSION:18.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu18
sed -e "s:VERSION:20.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu20
sed -e "s:VERSION:22.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu22

# Debian
#sed -e "s:VERSION:stretch:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianstretch
sed -e "s:VERSION:buster:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbuster
sed -e "s:VERSION:bullseye:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbullseye
sed -e "s:VERSION:bookworm:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbookworm

# Centos
sed -e "s:DISTRIBUTION:centos:g"     -e "s:VERSION:7.6.1810:g" -e "s:CENTOS7::g"  -e "s:CENTOS8:#:g" -e "s:ROCKYLINUX:#:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos7
sed -e "s:DISTRIBUTION:centos:g"     -e "s:VERSION:8:g"        -e "s:CENTOS7:#:g" -e "s:CENTOS8::g"  -e "s:ROCKYLINUX:#:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos8

# Rocky Linux
sed -e "s:DISTRIBUTION:rockylinux:g" -e "s:VERSION:8:g"        -e "s:CENTOS7:#:g" -e "s:CENTOS8:#:g" -e "s:ROCKYLINUX::g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:POWERTOOLS:powertools:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.rockylinux8
sed -e "s:DISTRIBUTION:rockylinux:g" -e "s:VERSION:9:g"        -e "s:CENTOS7:#:g" -e "s:CENTOS8:#:g" -e "s:ROCKYLINUX::g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:POWERTOOLS:crb:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.rockylinux9

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

        if [[ "${IMG}" =~ "debianbullseye.".*"ntap".* ]] ||
           [[ "${IMG}" =~ "centos.".*"ntap".* ]] || 
           [[ "${IMG}" =~ "rockylinux.".*"ntap".* ]]; then
            # Skip ntap for distrubutions with no package
            continue
        fi

        if [ "centos8.development.n2disk" == ${IMG} ] || 
           [ "centos8.stable.n2disk" == ${IMG} ] || 
           [ "rockylinux8.development.n2disk" == ${IMG} ] || 
           [ "rockylinux8.stable.n2disk" == ${IMG} ] ||
           [ "rockylinux9.development.n2disk" == ${IMG} ] || 
           [ "rockylinux9.stable.n2disk" == ${IMG} ]; then
            # Seems n2disk on centos8 attempts to install kernel-related stuff which is not supported on docker
            continue
        fi

        if [[ "${IMG}" =~ "centos8.".* ]]; then
            # Seems centos8 has the rpmdb broken on docker
            # https://github.com/ansible/awx/issues/6306
            # must skip until this is solved
            continue
        fi

        if [ "$IMG" = "seed" ]; then
            continue
        fi

        if [ "$PACKAGES_LIST" = "nedge" ] && [[ ${IMG} != ubuntu20.* ]]; then
            # nedge is supported on Ubuntu 20 only
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
            echo "FAIL Failed ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . [see ${OUT}/${IMG}${STABLE_SUFFIX}.log for more details]"
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
    sendError "${TAG} packages INSTALLATION failed on $INSTALLATION_FAILURES images" "Unable to build docker images: ${INSTALLATION_FAILED_IMAGES}" "" "2"
else
    sendSuccess "${TAG} packages INSTALLATION completed successfully" "All docker images built correctly."
fi

if [ "$FUNCTIONAL_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages TEST failed on $FUNCTIONAL_FAILURES images" "Unable to TEST docker images: ${FUNCTIONAL_FAILED_IMAGES}" "" "2"
else
    sendSuccess "${TAG} packages TEST completed successfully" "All docker images test correctly."
fi

