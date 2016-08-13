#!/bin/bash

MAIL_FROM=""
MAIL_TO=""

function usage {
    echo "Usage: run.sh [-m=stable] -f=<mail from> -t=<mail to>"
    echo ""
    echo "This tool will build some empty docker containers where ntop packages"
    echo "will be installed. This tool will make some tests and report"
    echo "results via email, thus it is necessary to set -f and -t."
    exit 0
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

/bin/rm -rf out
mkdir -p out

WHEEZY_BACKPORTS="RUN grep -q 'wheezy-backports' /etc/apt/sources.list || echo 'deb http\\://ftp.debian.org/debian wheezy-backports main' >> /etc/apt/sources.list"

SALTSTACK="RUN wget https\\://copr.fedoraproject.org/coprs/saltstack/zeromq4/repo/epel-6/saltstack-zeromq4-epel-6.repo\nRUN mv saltstack-zeromq4-epel-6.repo /etc/yum.repos.d/"

# Producing Dockerfile(s)
sed -e "s:VERSION:12.04:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > out/Dockerfile.ubuntu12
sed -e "s:VERSION:14.04:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > out/Dockerfile.ubuntu14
sed -e "s:VERSION:16.04:g"  -e "s:STABLE:${STABLE_SUFFIX}:g" docker/Dockerfile.ubuntu.seed > out/Dockerfile.ubuntu16
sed -e "s:VERSION:wheezy:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS:${WHEEZY_BACKPORTS}:g" docker/Dockerfile.debian.seed > out/Dockerfile.debianwheezy
sed -e "s:VERSION:jessie:g" -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:BACKPORTS::g" docker/Dockerfile.debian.seed > out/Dockerfile.debianjessie
sed -e "s:VERSION:6:g"      -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK:${SALTSTACK}:g" docker/Dockerfile.centos.seed > out/Dockerfile.centos6
sed -e "s:VERSION:7:g"      -e "s:STABLE:${STABLE_SUFFIX}:g" -e "s:SALTSTACK::g" docker/Dockerfile.centos.seed > out/Dockerfile.centos7

# Cleanup log
\rm -f *~ &> /dev/null

function cleanup {
	CONT=$(${DOCKER} ps -a -q)
	if [[ $CONT ]]; then
		echo "Cleaning up containers.."
		${DOCKER} rm -f ${CONT}
	fi

	IMGS=$(${DOCKER} images -q)
	if [[ $IMGS ]]; then
		echo "Cleaning up images.."
		${DOCKER} rmi ${IMGS}
	fi
}

# Deleting old containers/images
cleanup

FAILURES=0
FAILED_SYSTEMS=""

# Build containers
for DOCKERFILE in out/Dockerfile.*; do
	IMG="${DOCKERFILE##*.}"
	if [ "$IMG" = "seed" ]; then
		continue
	fi

	MAX_ATTEMPTS=2
	attempt=1
	while [ $attempt -le $MAX_ATTEMPTS ]
	do
	    echo "Building ${IMG}${STABLE_SUFFIX} [attempt: $attempt].."

	    ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . &> out/${IMG}${STABLE_SUFFIX}.log

	    if [ $? == 0 ]; then break; fi

	    let attempt=attempt+1
	done

	if [ "$attempt" -gt "$MAX_ATTEMPTS" ]
	then
	   echo "Failed ${DOCKER} build -t ${IMG} -f ${DOCKERFILE} . &> out/${IMG}${STABLE_SUFFIX}.log"
	   echo "Failure, see out/${IMG}${STABLE_SUFFIX}.log for more details"
	   let FAILURES=FAILURES+1
	   FAILED_SYSTEMS="${IMG} ${FAILED_SYSTEMS}"
	   # Sending mail with log
	   /bin/cat out/${IMG}${STABLE_SUFFIX}.log | mail -s "Packages installation failed on ${IMG}" -r $MAIL_FROM $MAIL_TO
	fi
	# rm ${DOCKERFILE}
done

if [ "$FAILURES" -ne "0" ]; then
	echo "Systems with errors: ${FAILED_SYSTEMS}\" | mail -s \"${TAG} packages installation failed on $FAILURES systems\" -r $MAIL_FROM $MAIL_TO"
else
	echo "All systems installed correctly." | mail -s "${TAG} packages installation completed successfully" -r  $MAIL_FROM $MAIL_TO
fi

# Cleaning up containers/images
cleanup
