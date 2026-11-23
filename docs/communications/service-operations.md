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
and number porting. The operator uses the carrier portal for those upstream
actions and records the resulting confirmations in Dashboard.

Customers bring new-number requests, port requests, emergency address
changes, and service issues to Lightek. Lightek submits and tracks the
upstream work with VoIP.ms and communicates the result to the customer.
Use the [VoIP.ms reseller program](https://main.voip.ms/partners/reseller-program/)
for the wholesale service model.

## Products and provisioning

Use Commerce service products with the slugs `lightek-voice` and
`lightek-internet` on a platform-owned storefront. Set the monthly or annual
price in Commerce. Confirm serviceability before offering a checkout. Neither
product is created or published automatically.

An eligible checkout snapshots the communications product type. After that
checkout settles through the existing signed Dymond Bank callback, open the
original order from the Dashboard queue. The order and its current
subscription need a settled billing receipt. Activation and restoration
recheck billing and store the receipt beside the evidence and operator.
If billing lapses, the Dashboard continues to show the last confirmed
technical state. An operator can record suspension after the corresponding
gateway or carrier operation.

## Voice as an installation add-on

Publish the recurring `lightek-voice` service product on the platform-owned
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
- Order or port the public number through VoIP.ms and route it to the SIP
  subaccount on the same PoP as the PBX.
- Verify inbound and outbound calls with audio and confirm the exact
  dispatchable location in the carrier portal. Use the carrier's
  [emergency calling test instructions](https://wiki.voip.ms/article/E911)
  for the test receipt.
- Record the carrier, SIP subaccount, public number and three call test
  references to complete the Dashboard activation. The carrier API checks
  routing and registration. The operator records the call and emergency
  calling evidence.
