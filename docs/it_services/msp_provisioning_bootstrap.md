# MSP staging provisioning bootstrap

Deploy the bootstrap PR on the existing control plane using the normal Gatekeeper release process. It targets the current `develop`, adds no database migration, and can be deployed before the combined MSP release. It stores the staging request and approval in the existing provisioning and Vault records.

## Set up dedicated staging references

1. In [Employee → Users → New user](https://lightekmcg.com/employee/users/new), create or confirm an active synthetic Dashboard user with role **Client** and email `staging-msp@example.test`. Save its sign-in credential through the approved password manager. Use a scoped staging-only Linode token.
2. In **Dashboard → Vault**, create or confirm the following entries with environment `staging` and explicit consumer and purpose fields. The names in the left column are examples. Enter sensitive values through the authenticated Vault UI.

| Vault slug | Payload key | Allowed consumer | Purpose |
| --- | --- | --- | --- |
| `staging-compute` | `token` | `Gatekeeper::Compute::Providers::LinodeAdapter` | `compute_management` |
| `staging-msp-owner` | `owner_password` | `Gatekeeper::WebsiteDeployment` | `website_deploy` |

3. In [Compute Providers](https://lightekmcg.com/dashboard/infrastructure/providers), confirm the existing `linode` provider is active and healthy. The request uses its Linode adapter with the staging Vault entry selected on the form.
4. In **Dashboard → Network & Domains → Domains & DNS**, verify that the existing `lightekmcg.com` GoDaddy zone is listed. The preparation form uses the same managed DNS lookup as website provisioning. It binds `batch-d-msp-r1.staging.lightekmcg.com` to `batch-d-msp-r1.staging` in that zone without changing DNS.
## Prepare and approve

1. Sign in as an active super admin. Open **Infrastructure → Provisioning requests → Prepare provisioning request** or visit [Prepare provisioning request](https://lightekmcg.com/dashboard/infrastructure/provisioning/new).
2. Enter `batch-d-msp-r1.staging.lightekmcg.com`, monthly cap `2400` cents and lifetime `48` hours. Select the staging client and its staging Vault references, review the region and certificate contact, and click **Prepare for approval**. If staging setup is incomplete, the form links to the relevant screens. The form uses one `g6-standard-2` instance with Ubuntu 24.04 and reads the live regional quote. Published North America compute pricing is about $1.73 for 48 hours at $0.036/hour.
3. Review the request’s hostname, owner, price and expiry. Click **Approve** and confirm. The page shows **approved / ready** and the approval audit entry. Share **Request #…** from that screen.

Preparation reserves the hostname and checks the catalog without a DNS credential. DNS access belongs to the separately authorized deployment. Approval records the funding decision. A separate Release Assurance deployment authorization is required to allocate compute. Reject an expired unallocated request before reserving its label again.

## Hand off to Release Assurance

Use a scoped Release Assurance worker connected to the approved Gatekeeper records. It can share the existing control plane’s database and Vault while using its own execution configuration. The worker must support the request's managed zone and exact staging record, use the approved staging Vault reference, and have the staging network allowlist and runtime dependencies specified in the Release Assurance runbook.

Import the reviewed combined candidate in Release Assurance. Attach the approved request ID, exact hostname, a budget no higher than the approval and a lifetime within the existing expiry. **Approve staging deployment** binds the candidate revision and staging request, then queues the isolated installation. The existing control plane can prepare and approve before this worker is available.
