# Lightek Voice and Internet service operations

Use **Dashboard → Settings → Email & communications → Voice & Internet
services** from a direct super administrator session. The workspace ties
each service to one paid Commerce subscription and its existing Dymond Bank
billing integration. It does not create a second payment processor connection
or initiate a charge.

## Who operates Lightek Voice

Lightek Voice is the customer-facing service. Lightek owns signup, pricing,
billing, PBX and extensions, and customer support. VoIP.ms is the wholesale
upstream for phone numbers, public telephone network interconnection, E911,
and number porting. The main installation sends carrier requests and
Dashboard shows the confirmations. Customers start new-number and port
requests in their own service workspace.
Use the [VoIP.ms reseller program](https://main.voip.ms/partners/reseller-program/)
for the wholesale service model.

## Products and provisioning

Use Commerce service products on the platform-owned storefront. Voice plans
use `lightek-voice` or a slug starting with `lightek-voice-`. Internet uses
`lightek-internet`. Create a separate product for each price and billing period,
such as `lightek-voice-standard-monthly` and `lightek-voice-standard-annual`.
The owner sees published plans and their monthly or annual prices. An existing
checkout retains its selected plan and price. Confirm serviceability before
publishing checkout offers.

An eligible checkout snapshots the communications product type. After that
checkout settles through the existing signed Dymond Bank callback, a Voice
add-on with completed signup details starts provisioning automatically. The
order and its current subscription need a settled billing receipt. Activation and restoration
recheck billing and store the receipt beside the evidence and operator.
If billing lapses, the Dashboard continues to show the last confirmed
technical state. An operator can record suspension after the corresponding
gateway or carrier operation.

## Voice as an installation add-on

Publish at least one recurring Voice service product on the platform-owned
storefront at the central federation origin once Voice is available for signup.
The owner of a connected paid installation opens **Your workspace → Your
services → Lightek Voice** to see the central price and start a separate
subscription checkout. The main installation matches the Voice order to the
authenticated peer and its billing account. It reuses an existing pending
order and sends payment through the central Dymond Bank-backed checkout.
Stripe payment verification uses the existing signed callback.

At signup, the owner chooses a new number in a US area code or asks to transfer
an existing US business landline. The owner confirms their emergency address.
For a transfer, the owner supplies the current carrier account details,
confirms their authorization, and uploads the current carrier invoice as a
PDF. Main stores the setup details in Vault. The customer page shows the
requested area code or the last four digits of the transfer number.

The child installation's scoped federation credential authorizes the request
back to main. VoIP.ms credentials stay in the central Vault. Verified checkout
or invoice payment schedules the background job immediately. It creates a unique
SIP subaccount and registers it on the Lightek PBX. It then buys a number
within the configured carrier limits or files the port with the supporting
PDF, then checks port status until the number appears in the carrier inventory.
After routing, it validates and provisions E911 and verifies the number route
and SIP registration. It installs the verified DID in the PBX and activates the
line. Customers see progress and can open **Set up your phone** for their own
phone credentials. The carrier credentials never go to the customer instance.
Dashboard records carrier results and flags exceptions for support. An
existing paid order missing signup details can be fulfilled from Dashboard.

## First Lightek-operated internet connection

Use a Linux Linode VPS as the first gateway host. Docker gives the test
subscriber and gateway a private Ethernet link for PPPoE. A separate gateway
interface provides WAN egress through the VPS. The subscriber can reach the
private probe and make one allowlisted public HTTPS request through the
gateway. The test does not advertise PPPoE on Linode's public interface.

```sh
sudo modprobe ppp_generic
sudo modprobe pppoe
sh deploy/communications/gateway/check.sh --live-egress
```

Allow the test to finish so it can verify suspension, reject reconnection,
match accounting start and stop, restore HTTPS, and remove its containers.
From a physical location, the next test also needs an Ethernet or bridged
link from the subscriber equipment to an access gateway and an upstream
handoff. Record the access connection, subscriber reference and traffic-test
receipt in Dashboard after verification.

## Deploy and verify the managed Voice PBX

Use a dedicated Asterisk 20 or newer host and a native Sidekiq process with
the main Rails deployment, Vault, database and Redis configuration. This
process consumes the `voice` queue. Run `bundle exec sidekiq -q voice` and
keep it running under the host service manager. Both this process and the
main web application need access to the same carrier account settings.

1. Enable API access and set the API password in VoIP.ms. Allowlist the
   outbound IP of the Voice worker and main web application. Save the API
   email and password in **Voice carrier settings** in Dashboard.
2. Install the configuration from `deploy/communications/pbx/` on the
   dedicated PBX. Put the SIP hostname's TLS certificate and private key in
   the paths listed in that directory's `pjsip.conf`. Use an internal RTP
   test before opening public calling. Allow UDP 5060 only from the selected
   provider PoP. The customer device uses TLS on TCP 5061 and SRTP. Restrict
   management access to the PBX host. Do not enable Asterisk's HTTP or AMI
   listeners.
3. Create `/var/lib/asterisk/lightek-voice` with its group set to the Asterisk
   group and mode `2770`. Grant write access to the dedicated Voice worker
   account only through that group. Asterisk reads its group-readable line
   files. Give that same worker local permission to use the Asterisk CLI
   control socket. Keep the Rails web process outside that group.
4. Verify a controlled pilot DID on this PBX through the chosen carrier PoP.
   Check inbound and outbound audio and verify the exact emergency address
   using the carrier's [E911 test instructions](https://wiki.voip.ms/article/E911).
   Record the three pilot references. Retest before switching to a different
   PBX or PoP.
5. Set the following deployment values on main and the Voice worker. Managed
   checkout becomes available after all are present and the central carrier
   credentials and appropriate Voice offers are configured.

| Setting | Value |
| --- | --- |
| `LIGHTEK_VOICE_CARRIER_ACCOUNT` | Six-digit VoIP.ms SIP account prefix |
| `LIGHTEK_VOICE_CARRIER_POP` | VoIP.ms PoP ID verified in the pilot |
| `LIGHTEK_VOICE_SIP_HOST` | Public TLS hostname of the tested PBX |
| `LIGHTEK_VOICE_MAX_SETUP_CENTS` | Maximum acceptable new DID wholesale setup charge in cents |
| `LIGHTEK_VOICE_MAX_MONTHLY_CENTS` | Maximum acceptable new DID wholesale monthly rate in cents |
| `LIGHTEK_VOICE_PBX_INBOUND_PROOF` | Pilot inbound audio test reference |
| `LIGHTEK_VOICE_PBX_OUTBOUND_PROOF` | Pilot outbound audio test reference |
| `LIGHTEK_VOICE_PBX_EMERGENCY_PROOF` | Pilot emergency calling test reference |

The managed flow assigns SIP credentials and routes automatically for each
paid order. Per-line activation receipts record the assigned number, verified
carrier route, E911 confirmation and the shared PBX deployment test references.
A customer can then use a compatible SIP softphone or desk phone. If a
carrier write has an uncertain result, reconcile it before submitting
another paid request.

For an earlier pilot that already has a SIP account, the legacy
`LIGHTEK_VOICE_PBX_ROUTES` map remains usable. That path retains individual
call-test evidence and manual activation.
