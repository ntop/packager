#!/bin/bash

UNAMESTR=`uname` # Used to determine if we are running on FreeBSD
UTILS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
DISCORD_SH="${UTILS_DIR}/discord.sh"

# Send an alert
function sendAlert {
    #
    # Parameters:
    #
    # $1: A symbol, e.g., :checkered_flag: or :triangular_flag_on_post: that will be prepended to the message title
    # $2: A title of the message
    # $3: Body of the message [OPTIONAL]
    # $4: A path to a file which will be send as body of the message. When $4 is defined, $3 is ignored. [OPTIONAL]
    # $5: Use the first N channels to send the message, out of those provided in DISCORD_WEBHOOK (Default: 1) [OPTIONAL]
    #

    NUM_CHANNELS="1"
    if [ -n "$5" ] ; then
        NUM_CHANNELS="$5"
    fi

    if [ -n "$MAIL_FROM" ] && [ -n "$MAIL_TO" ] ; then
	if [ -n "$4" ] ; then
	    if [ "${UNAMESTR}" == "FreeBSD" ]; then
		echo -e "Subject: $1 $2\n`/bin/cat $4`" | sendmail -f "${MAIL_FROM}" "${MAIL_TO}"
	    else
		/bin/cat $4 | mail -a "From: ${MAIL_FROM}" -s "$1 $2" "${MAIL_TO}"
	    fi
	else
	    if [ "${UNAMESTR}" == "FreeBSD" ]; then
		echo -e "Subject: $1 $2\n$3" | sendmail -f "${MAIL_FROM}" "${MAIL_TO}"
	    else
		echo "$3" | mail -a "From: ${MAIL_FROM}" -s "$1 $2" "${MAIL_TO}"
	    fi
	fi
    fi

    if [ -n "$DISCORD_WEBHOOK" ] ; then
	if [ -n "$4" ] ; then
	    # See https://github.com/ChaoticWeg/discord.sh for the fancy escaping via js
	    ${DISCORD_SH} --webhook-url "${DISCORD_WEBHOOK}" --channels "${NUM_CHANNELS}" --title "$1 $2" --text "$(jq -Rs . <$4 | cut -c 2- | rev | cut -c 2- | rev | tail -c 1000)" # at most 2k characters
	else
	    ${DISCORD_SH} --webhook-url "${DISCORD_WEBHOOK}" --channels "${NUM_CHANNELS}" --title "$1 $2" --text "$3"
	fi
    fi

    echo "[>] $2"
    echo "---"
    if [ -n "$4" ] ; then
	/bin/cat $4
    else
	echo "$3"
    fi
    echo "---"
}

# Send a success alert
function sendSuccess {
    sendAlert ":checkered_flag:" "$1" "$2" "$3" "$4"
}

# Send an error alert
function sendError {
    sendAlert ":triangular_flag_on_post:" "$1" "$2" "$3" "$4"
}
