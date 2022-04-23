#!/bin/bash
# Cloudflare Auto Waiting Room = CF Auto WR
# version 1.0.0

#config
debug_mode=0 # 1 = true, 0 = false, adds more logging & lets you edit vars to test the script
cf_apitoken=""
cf_zoneid=""
cf_roomid=""
upper_cpu_limit=35 # 10 = 10% load, 20 = 20% load.  Total load, taking into account # of cores
lower_cpu_limit=5
time_limit_before_revert=$((60 * 5)) # 5 minutes by default
#end config

# Functions

install() {
    mkdir /home/cfautowr &>/dev/null

    cat >/home/cfautowr/cfautowr.service <<EOF
[Unit]
Description=Automate Cloudflare Waiting Room

[Service]
ExecStart=/home/cfautowr/cfautowr.sh
User=root
EOF

  cat >/home/cfautowr/cfautowr.timer <<EOF
[Unit]
Description=Automate Cloudflare Waiting Room

[Timer]
AccuracySec=1
OnBootSec=60
OnUnitActiveSec=5

[Install]
WantedBy=timers.target
EOF

    chmod 644 /home/cfautowr/cfautowr.service

    systemctl enable /home/cfautowr/cfautowr.timer
    systemctl enable /home/cfautowr/cfautowr.service
    systemctl start cfautowr.timer

    echo "$(date) - cfautowr - Installed" >>/home/cfautowr/cfautowr.log

    exit
}

uninstall() {
    systemctl stop cfautowr.timer
    systemctl stop cfautowr.service
    systemctl disable cfautowr.timer
    systemctl disable cfautowr.service

    rm /home/cfautowr/cfstatus &>/dev/null
    rm /home/cfautowr/wrdisabledtime &>/dev/null
    rm /home/cfautowr/wrenabledtime &>/dev/null
    rm /home/cfautowr/cfautowr.timer
    rm /home/cfautowr/cfautowr.service

    echo "$(date) - cfautowr - Uninstalled" >>/home/cfautowr/cfautowr.log

    exit
}

disable_wr() {
    curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/waiting_rooms/$cf_roomid" \
        -H "Authorization: Bearer $cf_apitoken" \
        -H "Content-Type: application/json" \
        --data '{"suspended":true,"queue_all":true}' &>/dev/null

    # log time
    date +%s >/home/cfautowr/wrdisabledtime

    echo "$(date) - cfautowr - CPU Load: $curr_load - Disabled WR" >>/home/cfautowr/cfautowr.log
}

enable_wr() {
    curl -X PATCH "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/waiting_rooms/$cf_roomid" \
        -H "Authorization: Bearer $cf_apitoken" \
        -H "Content-Type: application/json" \
        --data '{"suspended":false,"queue_all":true}' &>/dev/null

    # log time
    date +%s >/home/cfautowr/wrenabledtime

    echo "$(date) - cfautowr - CPU Load: $curr_load - Enabled WR" >>/home/cfautowr/cfautowr.log
}

get_current_load() {
    currload=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    currload=$(echo "$currload/1" | bc)

    return $currload
}

get_room_status() {
    curl -X GET "https://api.cloudflare.com/client/v4/zones/$cf_zoneid/waiting_rooms/$cf_roomid" \
        -H "Authorization: Bearer $cf_apitoken" \
        -H "Content-Type: application/json" 2>/dev/null |
        awk -F":" '{ print $2 }' | sed -n 8p | tr -d ' ' | tr -d ',' | tr -d '\n' >/home/cfautowr/cfstatus

    room_status=$(cat /home/cfautowr/cfstatus)

    case $room_status in
    "false")
        return 1
        ;;
    "true")
        return 0
        ;;
    *)
        return 100 # error
        ;;
    esac
}

main() {
    # Get current protection level & load
    get_room_status
    curr_room_status=$?
    get_current_load
    curr_load=$?

    if [ $debug_mode == 1 ]; then
        debug_mode=1 # random inconsequential line needed to hide a dumb shellcheck error
        #edit vars here to debug the script
        #curr_load=5
        #time_limit_before_revert=15
    fi

    # If WR was recently enabled

    if [[ $curr_room_status == 1 ]]; then
        wr_enabled_time=$(cat /home/cfautowr/wrenabledtime)
        currenttime=$(date +%s)
        timediff=$((currenttime - wr_enabled_time))

        # If time limit has not passed do nothing
        if [[ $timediff -lt $time_limit_before_revert ]]; then
            if [ $debug_mode == 1 ]; then
                echo "$(date) - cfautowr - CPU Load: $curr_load - time limit has not passed regardless of CPU - do nothing" >>/home/cfautowr/cfautowr.log
            fi

            exit
        fi

        # If time limit has passed & cpu load has normalized, then disable WR
        if [[ $timediff -gt $time_limit_before_revert && $curr_load -lt $lower_cpu_limit ]]; then
            if [ $debug_mode == 1 ]; then
                echo "$(date) - cfautowr - CPU Load: $curr_load - time limit has passed - CPU Below threshhold" >>/home/cfautowr/cfautowr.log
            fi

            disable_wr

            exit
        fi

        # If time limit has passed & cpu load has not normalized, wait
        if [[ $timediff -gt $time_limit_before_revert && $curr_load -gt $lower_cpu_limit ]]; then
            if [ $debug_mode == 1 ]; then
                echo "$(date) - cfautowr - CPU Load: $curr_load - time limit has passed but CPU above threshhold, waiting out time limit" >>/home/cfautowr/cfautowr.log
            fi
        fi

        exit
    fi

    # If WR is not enabled, continue

    # Enable and Disable WR based on load

    #if load is higher than limit
    if [[ $curr_load -gt $upper_cpu_limit && $curr_room_status == 0 ]]; then
        enable_wr
    #else if load is lower than limit
    elif [[ $curr_load -lt $lower_cpu_limit && $curr_room_status == 1 ]]; then
        disable_wr
    else
        if [ $debug_mode == 1 ]; then
            echo "$(date) - cfautowr - CPU Load: $curr_load - no change necessary" >>/home/cfautowr/cfautowr.log
        fi
    fi
}

# End Functions

# Main -> command line arguments

if [ "$1" = '-install' ]; then
    install

    echo "$(date) - cfautowr - Installed" >>/home/cfautowr/cfautowr.log

    exit
elif [ "$1" = '-uninstall' ]; then
    uninstall

    echo "$(date) - cfautowr - Uninstalled" >>/home/cfautowr/cfautowr.log

    exit
elif [ "$1" = '-enable_wr' ]; then
    echo "$(date) - cfautowr - WR Manually Enabled" >>/home/cfautowr/cfautowr.log

    enable_wr

    exit
elif [ "$1" = '-disable_wr' ]; then
    echo "$(date) - cfautowr - WR Manually Disabled" >>/home/cfautowr/cfautowr.log

    disable_wr

    exit
elif [ -z "$1" ]; then
    main

    exit
else
    echo "cfautowr - Invalid argument"

    exit
fi
