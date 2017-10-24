#!/bin/bash

MAIL_FROM=""
MAIL_TO=""

function usage {
    echo "Usage: run.sh [--cleanup] | [ [-m=stable] -f=<mail from> -t=<mail to> ]"
    echo ""
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
	${DOCKER} rmi ${IMGS}
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
	-c|--cleanup)
	    cleanup
	    exit 0
	    ;;
	*)
	    # unknown option
	    ;;
    esac
done

if [ -z "$MAIL_FROM" ]; then
    usage
fi

if [ -z "$MAIL_TO" ]; then
    usage
fi

OUT="out-${TAG}"
/bin/rm -rf ${OUT}
mkdir -p ${OUT}/generic

WHEEZY_BACKPORTS="RUN grep -q 'wheezy-backports' /etc/apt/sources.list || echo 'deb http\\://ftp.debian.org/debian wheezy-backports main' >> /etc/apt/sources.list"

SALTSTACK="RUN wget https\\://copr.fedoraproject.org/coprs/saltstack/zeromq4/repo/epel-6/saltstack-zeromq4-epel-6.repo \&\& mv saltstack-zeromq4-epel-6.repo /etc/yum.repos.d/ "

# Producing Dockerfile(s)
sed -e "s:VERSION:12.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu12
sed -e "s:VERSION:14.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu14
sed -e "s:VERSION:16.04:g"   -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > ${OUT}/generic/Dockerfile.ubuntu16
sed -e "s:VERSION:wheezy:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS:${WHEEZY_BACKPORTS}:g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianwheezy
sed -e "s:VERSION:jessie:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianjessie
sed -e "s:VERSION:stretch:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" docker/Dockerfile.debian.seed > ${OUT}/generic/Dockerfile.debianstretch
sed -e "s:MINOR:6.8:g"       -e "s:CENTOS::g" -e "s:MAJOR:6:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK:${SALTSTACK}:g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos6
sed -e "s:MINOR:7.2.1511:g"  -e "s:CENTOS:#:g" -e "s:MAJOR:7:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK::g" docker/Dockerfile.centos.seed > ${OUT}/generic/Dockerfile.centos7

# Deleting old containers/images
#wait before cleaning up
#cleanup 

# #################################################################################################################
# INSTALLATION TESTS
#
# Build docker images for each supported distro and for each softare product so to test everything independently
# #################################################################################################################

FAILURES=0
FAILED_IMAGES=""
IMAGES=""

for ENTRYPOINT in entrypoints/*.sh; do
    ENTRYPOINT_SH=`basename ${ENTRYPOINT}`
    PACKAGES_LIST=`cat $ENTRYPOINT | grep TEST_PACKAGES | cut -d ':' -f 2 | xargs`

    for DOCKERFILE_GENERIC in ${OUT}/generic/Dockerfile.*; do
	IMG="${DOCKERFILE_GENERIC##*.}.${TAG}.${PACKAGES_LIST// /.}"
	DOCKERFILE=${OUT}/Dockerfile.${IMG}

	echo "Preparing docker image ${IMG} [packages: $PACKAGES_LIST] [entrypoint: $ENTRYPOINT]"

	if [ "$IMG" = "seed" ]; then
	    continue
	fi
	sed -e "s:PACKAGES_LIST:${PACKAGES_LIST}:g" \
	    -e "s:ENTRYPOINT_PATH:${ENTRYPOINT}:g" \
	    -e "s:ENTRYPOINT_SH:${ENTRYPOINT_SH}:g" \
	    ${DOCKERFILE_GENERIC} > ${DOCKERFILE}

	MAX_ATTEMPTS=2
	attempt=1
	while [ $attempt -le $MAX_ATTEMPTS ]
	do
	    echo -e "\t attempt: $attempt"
	    ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . &> ${OUT}/${IMG}${STABLE_SUFFIX}.log

	    if [ $? == 0 ]; then break; fi

	    let attempt=attempt+1
	done

	if [ "$attempt" -gt "$MAX_ATTEMPTS" ];
	then
	   echo "Failed ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . &> ${OUT}/${IMG}${STABLE_SUFFIX}.log"
	   echo "Failure, see ${OUT}/${IMG}${STABLE_SUFFIX}.log for more details"
	   let FAILURES=FAILURES+1
	   FAILED_IMAGES="${IMG} ${FAILED_IMAGES}"
	   # Sending mail with log
	   if [[ ! -s ${OUT}/${IMG}${STABLE_SUFFIX}.log ]]; then
	       echo "<< no log output during the build phase >>" >  ${OUT}/${IMG}${STABLE_SUFFIX}.log
	   fi
	   /bin/cat ${OUT}/${IMG}${STABLE_SUFFIX}.log | mail -s "Packages INSTALLATION failed on ${IMG} ${TAG}" -r $MAIL_FROM $MAIL_TO
	else
	    IMAGES="${IMAGES} ${IMG}"
	fi
    done
done

if [ "$FAILURES" -ne "0" ]; then
    echo "Unable to build docker images: ${FAILED_IMAGES}" | mail -s "${TAG} packages INSTALLATION failed on $FAILURES images" -r $MAIL_FROM $MAIL_TO
else
    echo "All docker images built correctly." | mail -s "${TAG} packages INSTALLATION completed successfully" -r  $MAIL_FROM $MAIL_TO
fi

#exit 1

# #################################################################################################################
# FUNCTIONAL TESTS
#
# Now that the docker containers have been successfully built it's time to actually test the installed software
# #################################################################################################################

FAILURES=0
FAILED_IMAGES=""

for IMG in ${IMAGES}; do
    if [[ $IMG ]]; then
	echo -n "Testing ${IMG}... "
	${DOCKER} run ${IMG} test &> ${OUT}/${IMG}${STABLE_SUFFIX}_test.log
	if [ $? != 0 ]; then
	    echo "FAIL Failed to execute: ${DOCKER} run ${IMG} test [see ${OUT}/${IMG}${STABLE_SUFFIX}_test.log for more details]"
	   let FAILURES=FAILURES+1
	   FAILED_IMAGES="${IMG} ${FAILED_IMAGES}"
	   # Sending mail with log
	   if [[ ! -s  ${OUT}/${IMG}${STABLE_SUFFIX}_test.log ]]; then
	       echo "<< no log output during the test phase >>" >   ${OUT}/${IMG}${STABLE_SUFFIX}_test.log
	   fi
	   /bin/cat ${OUT}/${IMG}${STABLE_SUFFIX}_test.log | mail -s "Packages TEST failed for ${IMG} ${TAG}" -r $MAIL_FROM $MAIL_TO
	else
	    echo "OK"
	fi
    fi
done

if [ "$FAILURES" -ne "0" ]; then
    echo "Unable to TEST docker images: ${FAILED_IMAGES}" | mail -s "${TAG} packages TEST failed on $FAILURES images" -r $MAIL_FROM $MAIL_TO
else
    if [ "${IMAGES}" != "" ] ; then
	echo "All docker images test correctly." | mail -s "${TAG} packages TEST completed successfully" -r  $MAIL_FROM $MAIL_TO
    fi
fi

# Cleaning up containers/images
# don't clean up the images/containers here, they may be used later
# cleanup
