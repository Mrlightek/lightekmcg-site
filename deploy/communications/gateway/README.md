# Lightek PPPoE access gateway pilot

The gateway terminates a subscriber PPPoE session, authenticates against local
FreeRADIUS, assigns a subscriber IPv4 address, and routes subscriber traffic
to an upstream test network. The test topology uses two isolated Docker bridge
networks. Only the gateway can forward between them. A default-drop forwarding
policy allows the authorized subscriber to reach the upstream probe.

| Component | Role |
| --- | --- |
| Subscriber | PPPoE client representing customer equipment |
| Gateway | PPPoE access concentrator, RADIUS client, IPv4 router and forwarding policy |
| FreeRADIUS | Local authentication and session start/stop accounting |
| Probe | Upstream destination with a return route to the subscriber |

Run on a Linux Docker host with Docker Compose v2, `openssl`, and kernel
support for PPP and PPPoE. On Ubuntu, load the host modules first.

```sh
sudo modprobe ppp_generic
sudo modprobe pppoe
sh deploy/communications/gateway/check.sh
```

The check creates a temporary subscriber password and isolated networks,
verifies forwarded traffic, suspends the subscriber and verifies that the active
session drops, a new PPP attempt is rejected, and accounting records match.
It restores the subscriber and verifies connectivity again. It then removes
the test stack.

The gateway serves one synthetic subscriber and one upstream probe. PAP and
the legacy pppd RADIUS plugin are confined to the test network and loopback
respectively. The pilot opens no public ports and has no production or
Dashboard integration. A field trial needs a private subscriber access link,
a hardened authentication and AAA transport, and a real upstream with a
return route. Tenant provisioning, plan enforcement, accounting retention
and incident workflows remain separate platform work.

## Linode WAN check

On a Linux VPS with Python 3, use `sh deploy/communications/gateway/check.sh
--live-egress`. The test adds a Docker egress network and verifies a
certificate-validated HTTPS request to `example.com` from the subscriber's
PPP interface. The gateway allows only that public address and TCP 443 on
its WAN path. Suspension must block both private probe traffic and that HTTPS
request, then restoration must recover both. Containers and temporary
networks are removed after the check.
