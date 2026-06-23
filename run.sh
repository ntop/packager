#!/bin/bash

MAIL_FROM=""
MAIL_TO=""
DISCORD_WEBHOOK=""
RELEASE=""  # e.g., rockylinux8, rockylinux9, rockylinux10, debianbullseye, debianbookworm, debiantrixie, ubuntu22, ubuntu24, ubuntu26
PACKAGE="" # e.g., cento, n2disk, nprobe, ntopng, nedge, nscrub, ntap, pfring

DOCKER="sudo docker"
TAG="development"
STABLE_SUFFIX=""
PRINT_VERSION=0

# Paths of the license files on the host to be mounted in each container for testing the license.
# Packages with no entry here will be skipped.
declare -A LICENSE_FILES=(
    [ntopng]="/etc/ntopng.license"
    [nprobe]="/etc/nprobe.license"
    [cento]="/etc/cento.license"
    [n2disk]="/etc/n2disk.license"
    [nscrub]="/etc/nscrub.license"
    [nedge]="/etc/nedge.license"
)

# Import functions to send out alerts
source utils/alerts.sh

function usage {
    echo "Usage: run.sh [--cleanup] | [-m=stable] [-f=<mail from>] [-t=<mail to>] [-d=<discord webhook>] [-r=<release>] [-p=<package>]"
    echo ""
    echo "-m=<branch>                : Select branch."
    echo "                             Available branches: dev (default), stable."
    echo "-r|--release=<release>     : Builds for a specific release. Optional, all releases are built when not specified."
    echo "                             Available releases: rockylinux8, rockylinux9, rockylinux10, debianbullseye (11), debianbookworm (12), debiantrixie (13), ubuntu22, ubuntu24, ubuntu26."
    echo "-p|--package=<package>     : Builds a specific package. Optional, all packages are built when not specified."
    echo "                             Available packages: cento, n2disk, nprobe, ntopng, nedge, nscrub, ntap, pfring."
    echo "-c|--cleanup               : clears all docker images and containers"
    echo "-V|--print-version         : skips all tests; just builds each image and prints \`--version\` (incl. system ID)"
    echo "                             via --net=host, so the system ID matches the host's"
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

        -V|--print-version)
            PRINT_VERSION=1
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
sed -e "s:VERSION:22.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu22
sed -e "s:VERSION:24.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu24
sed -e "s:VERSION:26.04:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu26

# Debian
sed -e "s:VERSION:bullseye:g" -e "s:BUSTER:#:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbullseye
sed -e "s:VERSION:bookworm:g" -e "s:BUSTER:#:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianbookworm
sed -e "s:VERSION:trixie:g"   -e "s:BUSTER:#:g" -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debiantrixie

# Rocky Linux
sed -e "s:DISTRIBUTION:rockylinux:g" -e "s:VERSION:8:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:POWERTOOLS:powertools:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.rockylinux8
sed -e "s:DISTRIBUTION:rockylinux:g" -e "s:VERSION:9:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:POWERTOOLS:crb:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.rockylinux9
sed -e "s:DISTRIBUTION:rockylinux/rockylinux:g" -e "s:VERSION:10.0:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:POWERTOOLS:crb:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.rockylinux10

INSTALLATION_FAILURES=0
INSTALLATION_FAILED_IMAGES=""

FUNCTIONAL_FAILURES=0
FUNCTIONAL_FAILED_IMAGES=""

VERSION_FAILURES=0
VERSION_FAILED_IMAGES=""

LICENSE_FAILURES=0
LICENSE_FAILED_IMAGES=""

IMAGES=""
TESTS_RUN=0

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
           [[ "${IMG}" =~ "rockylinux.".*"ntap".* ]]; then
            # Skip ntap for distrubutions with no package
            continue
        fi

        if [[ "${IMG}" =~ "rockylinux".*".n2disk".* ]]; then
            # Skip n2disk on RH as it attempts to install kernel-related stuff which is not supported on docker
            continue
        fi

        if [ "$IMG" = "seed" ]; then
            continue
        fi

        #if [ "$PACKAGES_LIST" = "nedge" ] && [[ ${IMG} != ubuntu24.* ]] && [[ ${IMG} != ubuntu26.development.* ]]; then
        if [ "$PACKAGES_LIST" = "nedge" ] && [[ ${IMG} != ubuntu24.* ]]; then
	    # nedge is supported on Ubuntu 20, 24 only
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

        let TESTS_RUN=TESTS_RUN+1
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
            sendError "Packages INSTALLATION failed on ${IMG} ${TAG}" "" "${OUT}/${IMG}${STABLE_SUFFIX}.log" "2"
        else
            IMAGES="${IMAGES} ${IMG}"

            if [ "$PRINT_VERSION" -eq 1 ]; then
                # #################################################################################################################
                # PRINT VERSION: just print --version (version, system ID, etc.) and skip tests.
                # Use --net=host so the system ID matches the host system ID.
                # #################################################################################################################

                echo "--- ${IMG} ---"
                ${DOCKER} run --net=host --rm ${IMG} print-version
                echo ""

                continue
            fi

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
                sendError "Packages TEST failed for ${IMG} ${TAG}" "" "${OUT}/${IMG}${STABLE_SUFFIX}_test.log" "2"
            else
                echo "OK"
            fi

            # #################################################################################################################
            # LICENSE TEST: verify that the package reports a valid license once the host license file is
            # mounted in the container (skipped when no license file is found for the package).
            # #################################################################################################################

            LICENSE_FILE="${LICENSE_FILES[$PACKAGES_LIST]}"
            if [ -n "$LICENSE_FILE" ] && [ -f "$LICENSE_FILE" ]; then
                echo -n "License check ${IMG}... "
                ${DOCKER} run --net=host -v ${LICENSE_FILE}:${LICENSE_FILE}:ro ${IMG} license-check &> ${OUT}/${IMG}${STABLE_SUFFIX}_license.log
                if [ $? != 0 ]; then
                    echo "FAIL [see ${OUT}/${IMG}${STABLE_SUFFIX}_license.log for more details]"
                    let LICENSE_FAILURES=LICENSE_FAILURES+1
                    LICENSE_FAILED_IMAGES="${IMG} ${LICENSE_FAILED_IMAGES}"
                    if [[ ! -s ${OUT}/${IMG}${STABLE_SUFFIX}_license.log ]]; then
                        echo "No log output during the LICENSE CHECK phase" > "${OUT}/${IMG}${STABLE_SUFFIX}_license.log"
                    fi
                    sendError "Packages LICENSE CHECK failed for ${IMG} ${TAG}" "" "${OUT}/${IMG}${STABLE_SUFFIX}_license.log" "2"
                else
                    echo "OK"
                fi
            fi

            # #################################################################################################################
            # VERSION TEST (dev packages only): verify that the version string contains today's date (YYMMDD)
            # #################################################################################################################

            if [ "$TAG" = "development" ]; then
                echo -n "Version check ${IMG}... "
                ${DOCKER} run ${IMG} version-check &> ${OUT}/${IMG}_version.log
                if [ $? != 0 ]; then
                    echo "FAIL [see ${OUT}/${IMG}_version.log for more details]"
                    let VERSION_FAILURES=VERSION_FAILURES+1
                    VERSION_FAILED_IMAGES="${IMG} ${VERSION_FAILED_IMAGES}"
                    if [[ ! -s ${OUT}/${IMG}_version.log ]]; then
                        echo "No log output during the VERSION CHECK phase" > "${OUT}/${IMG}_version.log"
                    fi
                    sendError "Packages VERSION CHECK failed for ${IMG} ${TAG}" "" "${OUT}/${IMG}_version.log" "2"
                else
                    echo "OK"
                fi
            fi

        fi
    done

    # Cleaning up created images/containers to make room on disk
    cleanup

done

if [ "$TESTS_RUN" -eq "0" ]; then
    sendError "${TAG} no tests were run" "No matching release/package combination found. Check -r and -p arguments." "" "2"
    exit 1
fi

if [ "$INSTALLATION_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages INSTALLATION failed on $INSTALLATION_FAILURES images" "Unable to build docker images: ${INSTALLATION_FAILED_IMAGES}" "" "2"
else
    sendSuccess "${TAG} packages INSTALLATION completed successfully" "All docker images built correctly."
fi

if [ "$PRINT_VERSION" -eq 1 ]; then
    # No other test ran in this mode
    exit 0
fi

if [ "$FUNCTIONAL_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages TEST failed on $FUNCTIONAL_FAILURES images" "Unable to TEST docker images: ${FUNCTIONAL_FAILED_IMAGES}" "" "2"
else
    sendSuccess "${TAG} packages TEST completed successfully" "All docker images test correctly."
fi

if [ "$LICENSE_FAILURES" -ne "0" ]; then
    sendError "${TAG} packages LICENSE CHECK failed on $LICENSE_FAILURES images" "License validation failed on: ${LICENSE_FAILED_IMAGES}" "" "2"
else
    sendSuccess "${TAG} packages LICENSE CHECK completed successfully" "All docker images report a valid license."
fi

if [ "$TAG" = "development" ]; then
    if [ "$VERSION_FAILURES" -ne "0" ]; then
        sendError "${TAG} packages VERSION CHECK failed on $VERSION_FAILURES images" "Version mismatch on: ${VERSION_FAILED_IMAGES}" "" "2"
    else
        sendSuccess "${TAG} packages VERSION CHECK completed successfully" "All docker images version check correctly."
    fi
fi

