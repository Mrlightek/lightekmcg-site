#!/bin/sh
set -eu

# These paths are disposable container configuration. Refuse to touch a host.
if [ "${1:-}" != "--isolated-container" ]; then
    printf '%s\n' 'Run the pilot through its Compose service.' >&2
    exit 2
fi

asterisk_pid=
radius_pid=
pilot_dir=$(mktemp -d)
radius_config=/etc/freeradius/3.0
radius_users=$radius_config/mods-config/files/authorize

cleanup() {
    if [ -n "$radius_pid" ]; then kill "$radius_pid" 2>/dev/null || :; fi
    if [ -n "$asterisk_pid" ]; then kill "$asterisk_pid" 2>/dev/null || :; fi
    wait
    rm -rf "$pilot_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077

sip_password=$(openssl rand -hex 20)
radius_password=$(openssl rand -hex 20)
radius_session="lightek-$(openssl rand -hex 12)"

mkdir -p /run/asterisk
chown asterisk:asterisk /run/asterisk
sed "s/__SIP_PASSWORD__/$sip_password/" pjsip.conf > /etc/asterisk/pjsip.conf
install -m 0640 extensions.conf /etc/asterisk/extensions.conf
chown root:asterisk /etc/asterisk/pjsip.conf /etc/asterisk/extensions.conf
chmod 0640 /etc/asterisk/pjsip.conf
asterisk -f -U asterisk -G asterisk > "$pilot_dir/asterisk.log" 2>&1 &
asterisk_pid=$!

for attempt in $(seq 1 20); do
    if grep -q 'Asterisk Ready' "$pilot_dir/asterisk.log"; then break; fi
    if [ "$attempt" -eq 20 ] || ! kill -0 "$asterisk_pid" 2>/dev/null; then
        cat "$pilot_dir/asterisk.log" >&2
        exit 1
    fi
    sleep 1
done
if ! sipp 127.0.0.1:5060 -sf echo.xml -i 127.0.0.1 -mi 127.0.0.1 \
    -p 5062 -au 2001 -ap "$sip_password" -m 1 -timeout 10s -timeout_error \
    </dev/null > "$pilot_dir/sipp.log" 2>&1; then
    cat "$pilot_dir/sipp.log" >&2
    exit 1
fi
printf '%s\n' 'PASS: Asterisk authenticated the test extension, answered, and ended a SIP call.'

install -d -m 0750 -o freerad -g freerad /run/freeradius
openssl rand -hex 24 > "$pilot_dir/radius-secret"
printf 'client lightek_pilot {\n ipaddr = 127.0.0.1\n secret = %s\n require_message_authenticator = yes\n}\n' \
    "$(cat "$pilot_dir/radius-secret")" > "$radius_config/clients.conf"
rm -f "$radius_config/sites-enabled/default" "$radius_config/sites-enabled/inner-tunnel"
# Load only the modules used by this private RADIUS site.
rm -f "$radius_config"/mods-enabled/*
for module in detail files pap; do
    ln -s "../mods-available/$module" "$radius_config/mods-enabled/$module"
done
install -m 0640 -o root -g freerad radius-site "$radius_config/sites-enabled/lightek-pilot"

radius_request() {
    port=$1
    request=$2
    expected=$3
    packet=$(cat)
    response=$(printf '%s\n' "$packet" | radclient -r 1 -t 3 -S "$pilot_dir/radius-secret" \
        "127.0.0.1:$port" "$request" 2>&1) || :
    if ! printf '%s\n' "$response" | grep -q "Received $expected "; then
        printf 'Expected %s for RADIUS %s.\n' "$expected" "$request" >&2
        return 1
    fi
}

authenticate() {
    radius_request 1812 auth "$1" <<PACKET
User-Name = "subscriber-pilot"
User-Password = "$radius_password"
Message-Authenticator = 0x00
PACKET
}

start_radius() {
    freeradius -f -l stdout > "$pilot_dir/radius.log" 2>&1 &
    radius_pid=$!
    for attempt in $(seq 1 15); do
        if authenticate "$1" 2>/dev/null; then return; fi
        if ! kill -0 "$radius_pid" 2>/dev/null; then break; fi
        sleep 1
    done
    printf 'FreeRADIUS did not return %s.\n' "$1" >&2
    cat "$pilot_dir/radius.log" >&2
    exit 1
}

set_subscriber() {
    if [ -n "$radius_pid" ]; then
        kill "$radius_pid"
        wait "$radius_pid" || :
        radius_pid=
    fi
    printf '%s\n' "$1" > "$radius_users"
}

set_subscriber "subscriber-pilot Cleartext-Password := \"$radius_password\""
start_radius Access-Accept
for status in Start Stop; do
    radius_request 1813 acct Accounting-Response <<PACKET
User-Name = "subscriber-pilot"
Acct-Session-Id = "$radius_session"
NAS-Port = 1
Acct-Status-Type = $status
PACKET
done

detail_file=$(grep -rlF "$radius_session" /var/log/freeradius/radacct)
awk -v session="$radius_session" '
    BEGIN { RS = "" }
    index($0, session) {
        if ($0 ~ /Acct-Status-Type = Start/) started = 1
        if ($0 ~ /Acct-Status-Type = Stop/) stopped = 1
    }
    END { exit !(started && stopped) }
' "$detail_file"
printf '%s\n' 'PASS: FreeRADIUS accepted the subscriber and persisted its session start and stop.'

set_subscriber 'subscriber-pilot Auth-Type := Reject'
start_radius Access-Reject
printf '%s\n' 'PASS: FreeRADIUS rejected the suspended subscriber.'

set_subscriber "subscriber-pilot Cleartext-Password := \"$radius_password\""
start_radius Access-Accept
printf '%s\n' 'PASS: FreeRADIUS accepted the restored subscriber.'
