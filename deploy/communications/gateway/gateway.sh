#!/bin/sh
set -eu
cd /opt/lightek-gateway

case ${PILOT_SUBSCRIBER_PASSWORD:-} in
    ''|*[!0-9a-f]*) printf '%s\n' 'Set a hexadecimal pilot subscriber password.' >&2; exit 2 ;;
esac

interface_for() {
    ip -o -4 address show to "$1/32" | awk '$2 ~ /^[[:alnum:]_]+$/ { print $2; exit }'
}

access_if=$(interface_for 172.30.248.2)
upstream_if=$(interface_for 172.30.249.2)
if [ -z "$access_if" ] || [ -z "$upstream_if" ]; then
    printf '%s\n' 'The gateway needs both its access-side and upstream IPv4 interfaces.' >&2
    exit 1
fi

state=/run/lightek-gateway
radius_config=/etc/freeradius/3.0
install -d -m 0700 "$state"
install -d -m 0750 -o freerad -g freerad /run/freeradius

# Keep the legacy pppd RADIUS exchange on loopback in the gateway container.
umask 077
secret=$(openssl rand -hex 24)
printf '127.0.0.1 %s\n' "$secret" > "$state/servers"
printf '%s\n' "$secret" > "$state/radclient-secret"
unset secret
touch "$state/port-map"
printf 'client pppoe {\n ipaddr = 127.0.0.1\n secret = %s\n require_message_authenticator = no\n limit_proxy_state = yes\n}\n' \
    "$(cat "$state/radclient-secret")" > "$radius_config/clients.conf"
rm -f "$radius_config/sites-enabled/default" "$radius_config/sites-enabled/inner-tunnel"
# Load only the modules used by this private RADIUS site.
rm -f "$radius_config"/mods-enabled/*
for module in always detail files pap; do
    ln -s "../mods-available/$module" "$radius_config/mods-enabled/$module"
done
install -m 0640 -o root -g freerad radius-site "$radius_config/sites-enabled/lightek-gateway"
install -m 0640 -o root -g freerad radius-access "$radius_config/mods-enabled/lightek-subscriber-access"
sed "s/__UPSTREAM_IF__/$upstream_if/g" forward.nft | nft -f -

if [ -n "${PILOT_HTTPS_IP:-}" ]; then
    case $PILOT_HTTPS_IP in
        *[!0-9.]*) printf '%s\n' 'Invalid pilot HTTPS destination.' >&2; exit 2 ;;
    esac
    egress_if=$(interface_for 172.30.250.2)
    if [ -z "$egress_if" ]; then
        printf '%s\n' 'The pilot HTTPS test needs its separate egress interface.' >&2
        exit 1
    fi
    sed -e "s/__EGRESS_IF__/$egress_if/g" -e "s/__HTTPS_IP__/$PILOT_HTTPS_IP/g" live-egress.nft | nft -f -
fi

# Run only the foreground services owned by this gateway.
radius_pid=
pppoe_pid=
cleanup() {
    rm -f "$state/ready"
    if [ -n "$pppoe_pid" ]; then kill "$pppoe_pid" 2>/dev/null || :; fi
    if [ -n "$radius_pid" ]; then kill "$radius_pid" 2>/dev/null || :; fi
    wait
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

sh ./access-policy.sh initialize
freeradius -f -l stdout &
radius_pid=$!
sh ./access-policy.sh ready
pppoe-server -F -k -I "$access_if" -C Lightek -S lightek -L 100.64.82.1 -R 100.64.82.2 \
    -N 1 -x 1 -O /opt/lightek-gateway/ppp-options -X "$state/pppoe.pid" &
pppoe_pid=$!

for attempt in $(seq 1 10); do
    kill -0 "$pppoe_pid"
    if [ -s "$state/pppoe.pid" ]; then break; fi
    if [ "$attempt" -eq 10 ]; then exit 1; fi
    sleep 1
done
touch "$state/ready"

while kill -0 "$radius_pid" 2>/dev/null && kill -0 "$pppoe_pid" 2>/dev/null; do
    sleep 1
done
printf '%s\n' 'A gateway process exited.' >&2
exit 1
