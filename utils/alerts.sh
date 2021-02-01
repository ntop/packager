#!/bin/bash

# Send an alert
function sendAlert {
    #
    # Parameters:
    #
    # $1: A symbol, e.g., :checkered_flag: or :triangular_flag_on_post: that will be prepended to the message title
    # $2: A title of the message
    # $3: Body of the message [OPTIONAL]
    # $4: A path to a file which will be send as body of the message. When $4 is defined, $3 is ignored. [OPTIONAL]
    #
    #
    if [ -n "$MAIL_FROM" ] && [ -n "$MAIL_TO" ] ; then
	if [ -n "$4" ] ; then
            /bin/cat $4 | mail -s "$1 $2" -r "${MAIL_FROM}" "${MAIL_TO}"
        else
            echo "$3" | mail -s "$1 $2" -r "${MAIL_FROM}" "${MAIL_TO}"
        fi
    fi

    if [ -n "$DISCORD_WEBHOOK" ] ; then
	if [ -n "$4" ] ; then
	    # See https://github.com/ChaoticWeg/discord.sh for the fancy escaping via js
	    ./discord.sh --webhook-url "${DISCORD_WEBHOOK}" --title "$1 $2" --text "$(jq -Rs . <$4 | cut -c 2- | rev | cut -c 2- | rev | tail -c 1000)" # at most 2k characters
        else
	    ./discord.sh --webhook-url "${DISCORD_WEBHOOK}" --title "$1 $2" --text "$3"
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
    sendAlert ":checkered_flag:" "$1" "$2" "$3"
}

# Send an error alert
function sendError {
    sendAlert ":triangular_flag_on_post:" "$1" "$2" "$3"
}
