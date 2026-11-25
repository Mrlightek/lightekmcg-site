# Feature Flags

Use **Dashboard → Operations → Feature Flags** to control when an implemented
feature becomes available. Only a directly signed-in platform operator can edit
or pause flags. Mutations require a freshly verified authenticator and are
recorded with the operator and the before-and-after settings.

Each flag starts paused. When enabled, it includes the union of these audiences:

- Direct Lightek employees and platform super administrators when staff is selected.
- Explicit account IDs.
- An agency's account and all descendant accounts when the agency ID is selected.
- Specific registered Fleet installation IDs, with matching ownership.
- A deterministic percentage of remaining accounts. Increasing the percentage
  keeps accounts already in the percentage cohort.

The application evaluates flags where the feature action runs. Register each
feature key in code and keep its existing permission, ownership, and plan checks.
Fleet installation targeting here controls central Dashboard actions for those
installations. It does not distribute configuration to separate Rails instances.

## First rollout: Managed DNS

1. Enable Managed DNS for the owner of a ready test installation. Set the
   percentage to zero and leave other audiences empty for an isolated pilot.
2. Follow the [PowerDNS pilot](lightek_authoritative_dns.md#stage-and-pilot).
3. Move additional agencies or installations into the rollout after verification.
4. **Pause rollout** overrides every audience and leaves the saved audience
   settings ready for reuse. New enrollments, staging and new cutover approvals
   stop. Existing domains continue resolving and owners retain record editing.
   Withdrawal and verification of an already-approved registrar change remain
   available.

Run the feature flag migration before serving the operator screen.
