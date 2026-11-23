# Telnyx cellular plans

This integration provisions cellular data and routes it through the customer's
WireGuard VPS. The carrier account and its trusted Hub must be provisioned
before taking orders. A hosted Rails session uses the platform's normal
authentication and MFA. A customer can retrieve only their own activation data.

## Carrier and network

1. Create a static-mode Telnyx Private Wireless Gateway and associate the
   configured SIM group with it. Connect the gateway's Telnyx network to
   the Ubuntu Hub using Cloud VPN. Have Telnyx route SIM internet-bound
   traffic through that VPN, with direct carrier internet breakout disabled.
   The Hub must receive original SIM source IPv4 addresses. Use **data.net**
   as the cellular APN. The CIDR admitted by the Hub must be reserved for static
   assignments. Confirm any dynamic APN pool is outside it. Keep the SIM group
   and its assigned addresses under
   this deployment's control.
2. The gateway manages the SIM IPv4 pool. Use the actual Telnyx gateway
   subnet in both Rails and the Hub's configuration. Use `10.50.0.0/16`
   only if Telnyx has made that range available and allocated it to your
   gateway. Telnyx's SIM update API can change the data cap and does not
   accept a caller-selected IPv4. The Rails record stores the IPv4 reported
   by the carrier, with a unique database constraint.
3. Use one dedicated WireGuard interface per customer on the Hub, named
   `wg-c` followed by the customer identifier. Configure `Table = off` and
   one peer with `AllowedIPs = 0.0.0.0/0` on that interface. Install a persistent
   directly connected host route for the customer tunnel IP in the Hub's
   main table. With wg-quick, a `PostUp` entry can install
   `ip -4 route replace CUSTOMER_PEER_IP/32 dev %i`, where CUSTOMER_PEER_IP is
   the actual peer tunnel address. Use a distinct tunnel address per
   customer. Keep the carrier interface separate, such as `wg-telnyx`, and
   prevent wg-quick from installing a main-table default through Telnyx.
4. At each customer VPS, allow the configured SIM subnet through the peer
   for the Hub and route that subnet back to the Hub. Enable IPv4 forwarding.
   Permit forwarding from the customer's WireGuard interface to the public WAN
   for the SIM subnet, permit established replies, and masquerade that subnet
   on the customer's WAN interface. Include the Hub's tunnel IPv4 in the
   customer peer's AllowedIPs for any tunnel management traffic. Disable
   strict reverse-path filtering on both VPN ingress paths.
5. Before sales, verify with a test device that outbound traffic uses the
   customer's VPS public address and that traffic cannot cross to another
   customer's WireGuard interface. Verify the VPN configuration blocks IPv6
   internet breakout. The included Hub rules allow only routed IPv4 SIM
   traffic and discard other traffic coming from the carrier tunnel.

## Install the Hub helper

On the dedicated Ubuntu Hub, install `wireguard-tools`, `iproute2`,
`nftables` and `python3`. Enable IPv4 forwarding with
`net.ipv4.ip_forward=1` in sysctl. Install the helper as root.

```sh
sudo install -d -m 0755 /usr/local/libexec
sudo install -m 0755 add_user_route.sh /usr/local/bin/add_user_route.sh
sudo install -m 0644 lightek_cellular_routes.py /usr/local/libexec/lightek_cellular_routes.py
sudo install -d -m 0700 /etc/lightek-cellular
sudo install -m 0644 lightek-cellular-routes.service /etc/systemd/system/
```

Create root-owned `/etc/lightek-cellular/hub.json` with keys
`carrier_interface` and `sim_ipv4_cidr`, using the live interface and subnet.
Reserve IPv4 rule priorities 1000 and 1001 and routing table IDs starting at
100 for this service. Keep the existing main-table and local rules. Make the
restoration unit depend on your actual WireGuard interface units with an
`After=` and `Requires=` systemd drop-in, then run
`sudo systemctl enable --now lightek-cellular-routes.service`.
Any other host firewall must permit the intended forwarded traffic. Manage the
`inet lightek_cellular` table through the helper alone.

Create a dedicated SSH service account. In sudoers, give that account
`NOPASSWD` access to `/usr/local/bin/add_user_route.sh` only. Disable key
forwarding, PTY, and port forwarding for the key, and restrict inbound SSH to
workers' IPs. Pin the Hub host key in the known-hosts file used by Rails.

The Hub stores only the route assignments in root-owned
`/var/lib/lightek-cellular/routes.json`. Preserve it with Hub backups. Flush and
rebuild the managed routes under a change window before transferring a SIM
between carrier groups or otherwise releasing an assigned SIM IP. Allowing
Telnyx to recycle an address that still has a Hub route can misdirect traffic.

## Rails configuration

Run the migration with the existing Rails deployment and run a worker that
consumes the default queue. Merge these settings into the web and worker
environments using the deployment secret manager.

| Setting | Expected value |
| --- | --- |
| `TELNYX_API_KEY` | Telnyx v2 API key. Used as Bearer authentication. |
| `TELNYX_PUBLIC_KEY` | Base64-encoded 32-byte webhook signing public key from Telnyx Mission Control. |
| `TELNYX_SIM_CARD_GROUP_ID` | UUID of the trusted static-mode Private Wireless Gateway SIM group. |
| `TELNYX_SIM_IPV4_CIDR` | The carrier's actual static pool, defaulting to `10.50.0.0/16`. Match the Hub configuration. |
| `HUB_VPS_HOST` | Hub SSH hostname or IP. |
| `HUB_VPS_USER` | Dedicated Hub routing SSH account. |
| `HUB_VPS_SSH_KEY` | Complete SSH private key as a multiline environment value. |
| `HUB_VPS_KNOWN_HOSTS_FILE` | Absolute path to a known-hosts file with the pinned Hub key. |
| `LOCKBOX_MASTER_KEY` | Existing 32-byte Lockbox master key in hex, or its existing Rails credentials equivalent. |

Dependencies are Faraday, RQRCode, ed25519, net-ssh and bcrypt_pbkdf, plus the
project's existing Lockbox setup. Configure the Telnyx notification channel to
deliver SIM status and data-usage events to `POST /webhooks/telnyx`.

## Order fulfillment and management

Call `Telnyx::ProvisionEsimService.call` from a trusted paid-order integration,
or use the platform-operator endpoint below. The operation creates a durable
request first, checks the Hub and peer, buys a single disabled eSIM, applies the
data cap, fetches the encrypted activation code, and enables the SIM. The first
device attach may be required for Telnyx to report its static address. The Hub
blocks traffic without a configured route. The router job retries during this
first attach and marks the subscription's route usable after SSH confirms it.

| Method and path | Who can use it | Input or response |
| --- | --- | --- |
| `POST /dashboard/user_esims` | Direct platform operator | `Idempotency-Key` UUID for the purchase and `user_esim` with `user_id`, `sim_card_group_id`, `plan_limit_mb`, `customer_wg_peer_ip`. |
| `GET /dashboard/user_esims/:id` | Owner | Provisioning state, confirmed carrier status, cap and assigned IP. |
| `GET /dashboard/user_esims/:id/activation` | Owner | Base64 PNG, LPA activation code and the APN setting. Send this response only to the customer. |
| `PATCH /dashboard/user_esims/:id/top_up` | Direct platform operator | `plan_limit_mb` is the **new total** in MB. An identical retry does not add more data. |
| `PATCH /dashboard/user_esims/:id/status` | Direct platform operator | `status` is `enabled` or `disabled`. Carrier completion is asynchronous. |

Write requests made with a browser session must include the normal Rails CSRF
token. The carrier endpoints and Hub job use server-side credentials only.
This API is a fulfillment interface. The platform's Dymond Bank checkout
should own retail prices, charged top-ups and paid receipts. No end-user route
can purchase an eSIM or bypass the payment system by modifying its cap.

If the purchase response is lost, the retry locates the SIM by its unique
carrier tag using the original request UUID. It never sends a second purchase
request for that UUID. If the attempt was rejected or no SIM materializes,
reconcile the tag in Telnyx before approving a new order. For a host or device
attach failure, resubmitting the same request UUID resumes the same eSIM.

## Verification

Run `ruby test/standalone/telnyx_cellular_test.rb` with the app dependencies
and SQLite available. Set `CELLULAR_TEST_DATABASE_URL` to a disposable
PostgreSQL test database to exercise the same tests against PostgreSQL. The
tests use carrier response fixtures and a fake SSH session. A launch check
still needs one live SIM, a signed webhook delivery and confirmed internet
egress through the intended customer VPS.

## Sell mobile data and a phone line together

Publish a platform-owned monthly USD Commerce service whose slug starts with
`lightek-voice-bundle-`. An eligible connected installation sees it in
**Phone & mobile data**. The purchase uses the existing signed Dymond Bank
settlement. One paid receipt starts eSIM and voice jobs independently, so a
pending phone-number port does not delay the eSIM. Owners view both states
and retrieve the eSIM from the same page.

Configure `LIGHTEK_CELLULAR_BUNDLES` as a JSON object on the main installation.
The worker needs the normal cellular and managed Voice credentials and queue
configuration. The bundle allowlist uses the authenticated federation peer's
key, which is an identifier. Keep raw bearer credentials out of the map.

| JSON key | Meaning |
| --- | --- |
| `peers` | Map from eligible federation peer keys to their dedicated customer VPS WireGuard peer IPv4 addresses. |
| `plans` | Map from Commerce product slug to a plan with integer `data_limit_mb` and `monthly_cost_cents` excluding the shared gateway. |
| `gateway_recovery_cents` | Monthly gateway cost to recover across the cohort. Defaults to 10000 cents for the published $100 charge. |
| `planned_paying_lines` | Paying accounts used for pricing. Defaults to 4, which budgets $25 per account toward $100. |
| `billing_fee_cents` | Fixed per-payment fees in cents. |
| `billing_fee_basis_points` | Total percentage fees, such as 360 for 3.6%. |
| `target_margin_basis_points` | Target contribution after payment fees, as a share of the selling price. Use 2500 for 25%. |

Each account's gateway contribution is built into the posted price. The app
does not add a separate gateway line or automatically reprice subscriptions.
Offers below the configured floor stay unavailable. The floor is computed as
`(non-gateway cost + gateway share + fixed fee) / (1 - fee rate - target margin)`,
rounded up to cents.

### U.S. pilot pricing at $25 per account toward the gateway

Using the public Telnyx U.S. Zone 1 tiers, budget data at full allowance.
Treat each line as the first consumption on the account when estimating the
plan's own cost. Pooling can lower the actual carrier bill. This example
budgets $19.50 per line on top of data and the $25 gateway share. The $19.50
includes $2 SIM service, $2 DID allowance, $1.50 E911, $6 voice usage,
$2 Hub share, $5 support and $1 for setup amortization. The customer VPS is
already paid for in this scenario. Price a new VPS, network charges, absorbed
taxes, and higher usage into `monthly_cost_cents` as applicable.

| Bundle | Data | Estimated cost before payment fees | Floor at 25% margin and 3.6% + $0.30 fees | Suggested monthly price |
| --- | --- | ---: | ---: | ---: |
| Starter | 250 MB + one line | $58.15 | $81.87 | $89 |
| Plus | 500 MB + one line | $67.90 | $95.52 | $105 |
| Pro | 1,000 MB + one line | $77.65 | $109.18 | $119 |

The $25 share recovers $100 with four paying accounts. An underfilled cohort
leaves part of the gateway invoice uncovered. Confirm the account's actual
rates and charges before publishing. Validate the paid-to-active flow against
the chosen VPS before taking orders. Set voice usage controls and verify
suspension on nonpayment before offering flat-rate service. This workflow
starts provisioning from a current paid receipt and exposes carrier-based
data limits. It does not implement voice minute caps, retail usage charges,
or continuous suspension on failed renewals.

Sources include [Telnyx U.S. IoT pricing](https://telnyx.com/pricing/iot-data-plans),
[Telnyx tiered billing](https://support.telnyx.com/en/articles/3296669-iot-sim-card-pricing),
[VoIP.ms E911](https://wiki.voip.ms/article/Emergency_Services),
[Stripe payment fees](https://stripe.com/pricing), and
[Stripe subscription billing fees](https://stripe.com/billing/pricing).

## New customers buying CMS and communications together

**My Applications** shows the existing CMS plans and the full package to new
buyers. Existing customers buy **Phone & mobile data** in their provisioned
CMS workspace. A full package is one platform-owned monthly USD
`lightek_instance` product with a slug starting `lightek-cms-bundle-` and
a working CMS subscription and hosting configuration. Add the product slug to
`LIGHTEK_CELLULAR_BUNDLES.signup_plans` using the existing
`data_limit_mb` and `monthly_cost_cents` keys. Include CMS delivery and
infrastructure in the full package's monthly cost.

The `signup_tunnels` map uses the assigned customer peer IPv4 as the key
and a Vault credential slug as the value. Pre-enroll one dedicated
WireGuard interface per slot on the Hub as above. Create a
`cellular_tunnel` credential for each slot and allow
`LightekCommunications::FullPackageJob` to read it for that purpose. Its
payload is `peer_ip`, the customer `private_key`, the corresponding Hub
`hub_public_key`, and the Hub's `endpoint` in host:port format. Use a
distinct key pair and Hub interface per slot. Keep signup slots separate
from the peer keys allocated to existing CMS customers. Apply the updated
Hub helper before offering the package.

Checkout reserves one slot and uses the normal paid CMS order. After the CMS
readiness checks pass, a worker configures WireGuard on that CMS server and
checks the handshake on both ends before starting phone and eSIM
provisioning. The order status remains in **My Applications** while CMS is
being prepared. Once the workspace opens, **Phone & mobile data** shows
the activation progress. An abandoned, canceled order that never settled
can release its unused tunnel for the next signup.
