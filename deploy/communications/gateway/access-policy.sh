#!/bin/sh
set -eu

state=/run/lightek-gateway
authorize=/etc/freeradius/3.0/mods-config/files/authorize
subscriber_ip=100.64.82.2
active=/run/freeradius/lightek-subscriber-active

# Avoid interleaving policy writes and session teardown.
exec 9>"$state/policy.lock"
flock 9

confirm_radius() {
    expected=$1
    for attempt in $(seq 1 12); do
        response=$(printf 'User-Name = "subscriber-pilot"\nUser-Password = "%s"\n' \
            "$PILOT_SUBSCRIBER_PASSWORD" | radclient -r 1 -t 3 -S "$state/radclient-secret" \
            127.0.0.1:1812 auth 2>&1) || :
        if printf '%s\n' "$response" | grep -q "Received $expected "; then return; fi
        sleep 1
    done
    printf 'RADIUS did not confirm %s.\n' "$expected" >&2
    return 1
}

disconnect() {
    session_pid_file=/run/ppp-lightek-pilot.pid
    if [ ! -s "$session_pid_file" ]; then return; fi
    pid=$(sed -n '1p' "$session_pid_file")
    case $pid in ''|*[!0-9]*) return 1 ;; esac
    if [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = pppd ]; then
        kill -TERM "$pid" 2>/dev/null || :
    fi
}

enable_forwarding() {
    nft -f - <<RULES
flush set inet lightek_gateway allowed
add element inet lightek_gateway allowed { $subscriber_ip }
RULES
}

case ${1:-} in
    initialize)
        printf 'subscriber-pilot Cleartext-Password := "%s"\n    Framed-IP-Address := %s\n' \
            "$PILOT_SUBSCRIBER_PASSWORD" "$subscriber_ip" > "$authorize"
        touch "$active"
        ;;
    ready)
        confirm_radius Access-Accept
        enable_forwarding
        ;;
    suspend)
        nft flush set inet lightek_gateway allowed
        rm -f "$active"
        disconnect
        confirm_radius Access-Reject
        ;;
    restore)
        touch "$active"
        confirm_radius Access-Accept
        enable_forwarding
        ;;
    *)
        printf '%s\n' 'Use suspend or restore.' >&2
        exit 2
        ;;
esac
