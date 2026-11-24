#!/bin/sh
set -eu

case ${PILOT_SUBSCRIBER_PASSWORD:-} in
    ''|*[!0-9a-f]*) printf '%s\n' 'Set a hexadecimal pilot subscriber password.' >&2; exit 2 ;;
esac

access_if=$(ip -o -4 address show to 172.30.248.3/32 | awk '$2 ~ /^[[:alnum:]_]+$/ { print $2; exit }')
if [ -z "$access_if" ]; then
    printf '%s\n' 'The subscriber needs its access-side IPv4 interface.' >&2
    exit 1
fi

# The CPE has a route to the probe only while PPP has negotiated IPv4.
umask 077
cat > /etc/ppp/peers/lightek-pilot <<OPTIONS
plugin rp-pppoe.so
nic-$access_if
user subscriber-pilot
password $PILOT_SUBSCRIBER_PASSWORD
noauth
noipdefault
defaultroute
noipv6
persist
maxfail 0
holdoff 2
lcp-echo-interval 5
lcp-echo-failure 3
nodetach
logfd 1
OPTIONS

exec pppd call lightek-pilot
