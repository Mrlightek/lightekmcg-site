# Optional Lightek managed DNS

Customers can continue pointing a DNS A record to their VPS. Managed DNS is a
separate, per-domain enrollment from **My Applications → Managed DNS** on a
ready installation with a customer domain. The owner or an agency that manages
the owner can request it. For a site at `www.example.com`, enrollment covers
the whole `example.com` zone. Platform-owned Lightek domains do not enroll
through customer orders.

## Configure the managed provider

1. Use a Lightek-controlled Cloudflare account with account custom nameservers
   enabled. Configure `ns1.lightekmcg.com` and `ns2.lightekmcg.com` in one
   account custom nameserver set. Publish the provider-assigned A and AAAA
   addresses at the authoritative DNS provider for the nameserver domain and
   register the glue records where required. Use the provider-assigned addresses
   and leave the existing delegation for the Lightek website in place.
2. Set `LIGHTEK_MANAGED_DNS_ACCOUNT_ID` to the account ID. If using other
   Lightek-owned names, set `LIGHTEK_MANAGED_DNS_NAMESERVERS` to the complete
   comma-separated set.
3. In Lightek Vault, configure `cloudflare-managed-dns` (override with
   `LIGHTEK_MANAGED_DNS_VAULT_SLUG`) with a scoped API token in the `token`
   field. Grant Account Settings Read, Zone Read, and DNS Read for the managed
   account and relevant zones. Allow consumer `LightekManagedDns::Cloudflare`
   and purpose `dns_management` in the Vault policy.
4. Deploy the application and run the database migration. Pilot the flow with
   a domain Lightek controls before accepting a customer nameserver change.

See [Cloudflare account custom nameservers](https://developers.cloudflare.com/dns/nameservers/custom-nameservers/account-custom-nameservers/).

## Migrate a domain

1. The customer or managing agency opts in and publishes the displayed TXT
   challenge at their current DNS provider.
2. A Lightek operator opens the **Managed DNS** link on the order in
   **Dashboard → Application installations**. Export the current zone, create
   a pending zone in the Lightek Cloudflare account, import the records, and
   assign the branded account nameserver set to that zone. The application's
   hostname needs a DNS-only A record to its allocated VPS. Keep the old DNS
   provider serving traffic.
3. Enter the provider zone ID and choose **Stage for review**. Compare the
   provider's staged records against the existing zone. Check email, TXT
   verification, CAA, delegated subdomains, and equivalent replacement for any
   provider-specific records. Follow the provider's DNSSEC transition guidance for
   zones with a DS record. Approve after this comparison is complete.
4. The customer changes nameservers at the registrar using the approved list.
   **Verify nameservers** checks provider activation, public nameservers,
   and the website IPv4 address. The Dashboard shows the bound provider's
   DNS records. Change records in Cloudflare.

If the migration needs to be reversed, first ensure the old provider serves
the current records and that the DNSSEC transition is accounted for. Restore
the previous nameservers at the registrar. Once public DNS reports the old
servers, withdraw the request. Withdrawal preserves the provider zone.

See [Cloudflare DNSSEC migration](https://developers.cloudflare.com/dns/dnssec/dnssec-active-migration/).
