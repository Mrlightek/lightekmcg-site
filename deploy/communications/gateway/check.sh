#!/bin/sh
set -eu

cd "$(dirname "$0")"
case ${1:-} in
    "") live_egress=no ;;
    --live-egress) live_egress=yes ;;
    *) printf '%s\n' 'Usage: check.sh [--live-egress]' >&2; exit 2 ;;
esac
if [ ! -c /dev/ppp ]; then
    printf '%s\n' 'The Linux Docker host must provide /dev/ppp and the PPPoE kernel module.' >&2
    exit 2
fi
PILOT_SUBSCRIBER_PASSWORD=$(openssl rand -hex 20)
export PILOT_SUBSCRIBER_PASSWORD

if [ "$live_egress" = yes ]; then
    PILOT_HTTPS_IP=$(python3 - <<'PYTHON'
import ipaddress
import socket
for _, _, _, _, (address, _) in socket.getaddrinfo("example.com", 443, socket.AF_INET, socket.SOCK_STREAM):
    if ipaddress.IPv4Address(address).is_global:
        print(address)
        break
else:
    raise SystemExit("Could not resolve a public address for example.com.")
PYTHON
    )
    export PILOT_HTTPS_IP
fi

compose() {
    if [ "$live_egress" = yes ]; then
        docker compose -p "lightek-gateway-pilot-$$" -f compose.yml -f live-egress.yml "$@"
    else
        docker compose -p "lightek-gateway-pilot-$$" -f compose.yml "$@"
    fi
}

cleanup() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then compose logs >&2 || :; fi
    compose down --timeout 5 --remove-orphans || :
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

await() {
    description=$1
    shift
    for attempt in $(seq 1 25); do
        if "$@" >/dev/null 2>&1; then return; fi
        sleep 1
    done
    printf 'Timed out waiting for %s.\n' "$description" >&2
    return 1
}

passes_probe() {
    compose exec -T subscriber ping -I ppp0 -c 1 -W 1 172.30.249.3
}

passes_https() {
    [ "$live_egress" = yes ] || return 1
    compose exec -T subscriber curl --ipv4 --interface ppp0 --noproxy '*' --fail --silent \
        --max-time 6 --resolve "example.com:443:$PILOT_HTTPS_IP" --output /dev/null https://example.com/
}

session_closed() {
    compose exec -T gateway sh -c '! ip -4 address show dev ppp0 2>/dev/null | grep -q "100.64.82.1"'
}

reconnect_rejected() {
    compose logs --no-color subscriber | grep -q 'PAP authentication failed'
}

verify_accounting() {
    compose exec -T gateway awk '
        BEGIN { RS = ""; FS = "\n" }
        /User-Name = "subscriber-pilot"/ {
            session = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /Acct-Session-Id = "/) {
                    split($i, fields, "\"")
                    session = fields[2]
                }
            }
            if (session != "") {
                if (/Acct-Status-Type = Start/) start[session] = 1
                if (/Acct-Status-Type = Stop/) stop[session] = 1
            }
        }
        END {
            paired = 0
            for (session in start) if (stop[session]) paired = 1
            exit !paired
        }
    ' /var/log/freeradius/radacct/127.0.0.1/detail-$(date -u +%Y%m%d)
}

compose up --build --wait --wait-timeout 75
await 'routed traffic from the authenticated CPE to the upstream probe' passes_probe
printf '%s\n' 'PASS: The authenticated PPPoE subscriber can reach the upstream probe.'
if [ "$live_egress" = yes ]; then
    await 'public HTTPS through the authenticated PPPoE session' passes_https
    printf '%s\n' 'PASS: Public HTTPS traversed PPPoE and the gateway WAN.'
fi

compose exec -T gateway sh ./access-policy.sh suspend
await 'the active IPv4 session to close' session_closed
await 'a PPPoE reconnect to fail authentication' reconnect_rejected
if passes_probe || passes_https; then
    printf '%s\n' 'The suspended subscriber can still reach the probe.' >&2
    exit 1
fi
await 'matching RADIUS accounting start and stop records' verify_accounting
printf '%s\n' 'PASS: Suspension drops the active session, blocks traffic and reconnects, and records a matching accounting stop.'

compose exec -T gateway sh ./access-policy.sh restore
await 'routed traffic after restoration' passes_probe
if [ "$live_egress" = yes ]; then await 'public HTTPS after restoration' passes_https; fi
printf '%s\n' 'PASS: Restoration lets the subscriber reconnect and reach the upstream probe.'
