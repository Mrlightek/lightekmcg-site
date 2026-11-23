#!/bin/sh
set -eu

case ${PILOT_SUBSCRIBER_PASSWORD:-} in
    ''|*[!0-9a-f]*) printf '%s\n' 'Set a hexadecimal pilot subscriber password.' >&2; exit 2 ;;
esac

# The CPE has a route to the probe only while PPP has negotiated IPv4.
umask 077
cat > /etc/ppp/peers/lightek-pilot <<OPTIONS
plugin rp-pppoe.so
nic-access0
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
