# Lightek authoritative DNS

Lightek PowerDNS is the default for new **My Applications → Managed DNS**
enrollments. The opted-in domain stays with its registrar. Customers who use an
A record can keep their current DNS provider. Earlier enrollments retain their
provider, and a withdrawn request can enroll again under the current default.
Set `LIGHTEK_MANAGED_DNS_PROVIDER=cloudflare` only to select the
[Cloudflare backend](managed_dns.md) for new requests.

## Set up the DNS servers

- Run one private PowerDNS Authoritative primary and at least two public
  authoritative secondaries on independent networks. Each secondary keeps a
  local database. Use the packaged SQLite backend and initialize each node
  with the schema from its installed PowerDNS version. The
  [primary](../deploy/powerdns/primary.conf.example) and
  [secondary](../deploy/powerdns/secondary.conf.example) are configuration
  examples. Use a supported, patched version on all nodes.
- Expose UDP and TCP 53 on the secondaries. Restrict primary DNS to the
  secondary transfer network. Keep the primary API on loopback and give
  Rails a private HTTPS path with a trusted certificate and an allowlist
  for the app host. Configure per-zone TSIG transfers on both ends. Keep
  recursion, dynamic updates, unauthenticated AXFR and public admin access
  disabled.
- Point `ns1.lightekmcg.com` and `ns2.lightekmcg.com` at the two public
  nameservers. Publish the addresses in the existing Lightek DNS zone and
  register the names at the registrar with the same addresses where glue
  is needed. Keep the existing delegation of `lightekmcg.com`.
- Set `LIGHTEK_POWERDNS_API_URL` to the private HTTPS origin. Set
  `LIGHTEK_POWERDNS_PUBLIC_ENDPOINTS` to a JSON map from each nameserver
  name to an array of its published addresses. Set
  `LIGHTEK_MANAGED_DNS_NAMESERVERS` if using different names. The
  Dashboard checks each configured address. Add the primary API key
  to Vault as `api_key` in `lightek-powerdns` (override with
  `LIGHTEK_POWERDNS_VAULT_SLUG`), scoped to
  `LightekManagedDns::PowerDns` for `dns_management`. Run the migration.

## Stage and pilot

1. Use a ready hosting order and a separate Lightek-owned test domain. Opt in
   and publish the ownership TXT record at the current authoritative provider.
2. Export its entire zone and keep a protected copy. On the private primary,
   import the reviewed file with `pdnsutil zone load`, set the zone kind to
   primary, replace its apex NS set with the Lightek nameservers, and set a
   suitable SOA. Configure `SOA-EDIT-API=INCREASE` and
   `ALSO-NOTIFY` for all secondaries. Run `pdnsutil zone check` and
   verify the VPS hostname still has its DNS-only A record.
3. Pre-provision a secondary zone on each public node with
   `pdnsutil zone create-secondary`. Install the shared transfer credential
   via a protected channel and activate it on the primary and secondaries
   with `pdnsutil tsigkey activate`. Confirm transfers from the private
   primary. The modern command forms shown here are for PowerDNS 5.x.
   Consult the installed manual for 4.x command names.
4. In **Managed DNS**, stage the imported zone. The app directly checks
   authoritative TCP answers from every configured public nameserver
   address, including the SOA serial, apex NS records and website
   address. The operator compares the imported records against the
   original export, including mail, TXT verification, CAA and child
   delegations, then approves the instructions.
5. Verify UDP and TCP from an external probe. Test a record edit and confirm
   the updated SOA serial and value at every secondary. Stop the primary in
   the lab and verify both secondaries still answer from their local
   copies. Back up and restore the primary database, including DNSSEC keys,
   transfers and metadata, into an isolated instance. Use a consistent SQLite
   backup, and protect backups and key material separately from app logs.
6. Inventory registrar DS records and establish the DNSSEC transition before
   changing delegation. Verify the signed zone and DS with a validating resolver
   on the pilot. Monitor authoritative reachability, SOA drift, expiration,
   signature validity, and website and mail records. Keep the original DNS
   service intact until the test passes. The Dashboard's TCP check does not
   replace UDP, DNSSEC or mail verification.
7. Change nameservers at the test domain's registrar. Use **Verify nameservers**
   to confirm public delegation and the website address. If reverting, restore
   the previous nameservers and compatible DS records before withdrawing.

## Record changes

The domain owner, managing agency or Lightek operator can add, replace or remove
supported record sets after verified cutover and a fresh authenticator check.
The editor protects the hosted website's address and ownership challenge.
Changes are accepted by the primary first. Use **Verify nameservers** to confirm
the new serial on all public servers. Reload and inspect the zone before retrying
if the API connection fails during a write. Request and acceptance metadata are
logged with actor and enrollment IDs. Record values and API credentials are
excluded from those logs.

PowerDNS reference: [zone API](https://doc.powerdns.com/authoritative/http-api/zone.html),
[transfer authentication](https://doc.powerdns.com/authoritative/tsig.html),
[DNSSEC](https://doc.powerdns.com/authoritative/dnssec/index.html).
