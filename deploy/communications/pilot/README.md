# Lightek Communications pilot

Run this isolated pilot from an Ubuntu host with Docker and the Compose plugin.

```sh
docker compose -f deploy/communications/pilot/compose.yml run --build --rm pilot
```

The image build fetches Ubuntu packages. The running container has no network
besides loopback and generates temporary credentials on each run. It uses no
Lightek customer data and can run independently of Rails and the mail host.

The command exits successfully only after both checks pass.

- **Voice.** Asterisk challenges a SIPp call from extension 2001, answers
  at extension 600, and accepts the hangup. The test exercises authenticated
  SIP signaling to the echo dial plan. It does not assert RTP audio delivery.
- **Internet.** FreeRADIUS accepts a synthetic subscriber, returns accounting
  responses for session start and stop, and writes both records. The pilot
  changes the subscriber policy, then confirms rejection on suspension and
  acceptance on restoration. It exercises policy at the RADIUS server using a
  synthetic client. An access gateway is still needed to enforce that policy and
  disconnect an already active subscriber.

For service trials, the Dashboard and Gatekeeper will need to own tenant
provisioning. Dymond Bank will own the billing lifecycle. The Voice trial needs
a private call test with two endpoints, then a carrier trunk, an assigned public
number, and verified emergency calling before offering public service. The
Internet trial needs either a wholesale access integration or a Lightek-operated
gateway and access network. Use an actual subscriber connection to verify
activation, session visibility, suspension, and restoration.

For the routed subscriber lifecycle, see the
[PPPoE access gateway pilot](../gateway/README.md).
