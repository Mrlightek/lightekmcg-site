# Lightek Voice and Internet service operations

Use **Dashboard → Settings → Email & communications → Voice & Internet
services** from a direct super administrator session. The workspace ties
each service to one paid Commerce subscription and its existing Dymond Bank
billing integration. It does not create a second payment processor connection
or initiate a charge.

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
- After you acquire a public number, route it to the SIP subaccount on the
  same PoP as the PBX.
- Verify inbound and outbound calls with audio and confirm the exact
  dispatchable location in the carrier portal. Use the carrier's
  [emergency calling test instructions](https://wiki.voip.ms/article/E911)
  for the test receipt.
- Record the carrier, SIP subaccount, public number and three call test
  references to complete the Dashboard activation. The carrier API checks
  routing and registration. The operator records the call and emergency
  calling evidence.
