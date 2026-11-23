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
and number porting. Open the paid Voice service in Dashboard to send these
requests from the main installation and view the carrier confirmations.

Customers bring new-number requests, port requests, emergency address
changes, and service issues to Lightek. Lightek submits and tracks the
upstream work with VoIP.ms and communicates the result to the customer.
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
checkout settles through the existing signed Dymond Bank callback, open the
original order from the Dashboard queue. The order and its current
subscription need a settled billing receipt. Activation and restoration
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

The child installation's scoped federation credential authorizes the request
back to main. VoIP.ms credentials stay in the central Vault. Customer
installations receive checkout and service status only. A paid order appears
in the central communications queue, where the operator can see the customer
installation and complete the carrier setup and activation checks. Customers
see the resulting status on their own Lightek Voice page.

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

## First public business number through VoIP.ms

- Use a dedicated Asterisk host for the PBX. Create a SIP subaccount in the
  carrier portal and register it with a VoIP.ms PoP. SIP registration can be
  tested before a public number is ordered.
- Configure your Asterisk trunk according to the carrier's [PJSIP guide](https://wiki.voip.ms/article/Asterisk_PJSIP).
  Keep SIP credentials on the PBX through its credential management.
- Enable the account API, set its separate API password, and allowlist the
  Dashboard server's outbound IP. Save the carrier email and API password
  under **Voice carrier settings**. Rails stores them in Vault and uses two
  read-only lookups to confirm SIP registration and, when provided, the exact
  number route. In **Check SIP registration**, leave the public number blank
  until one is assigned.
- Open the paid Voice service in Dashboard. Search US numbers by area code
  and order the selected DID with its SIP subaccount, PoP and carrier rate.
  To transfer an existing US business landline, submit the authorized port,
  send the supporting invoice PDF, refresh the carrier status and route the
  number after it appears in the carrier inventory.
- Enter the customer-confirmed US emergency address in Dashboard. Lightek
  verifies the number route, validates the address, provisions E911 through
  VoIP.ms and checks the returned record. Carrier writes hold an audit
  receipt immediately before submission. If the outcome is unclear, review
  the carrier result before another request.
- Verify inbound and outbound calls with audio and confirm the exact
  dispatchable location in the carrier portal. Use the carrier's
  [emergency calling test instructions](https://wiki.voip.ms/article/E911)
  for the test receipt.
- Record the carrier, SIP subaccount, public number and three call test
  references to complete the Dashboard activation. The carrier API checks
  routing and registration. The operator records the call and emergency
  calling evidence.
