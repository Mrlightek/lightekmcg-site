# First sign-in, MFA and recovery

## Why production opens Sign-in security

After the enterprise identity update, privileged platform accounts and accounts covered by an employer MFA policy must enroll an authenticator. A password-only enrollment session cannot open ordinary business workspaces until verification succeeds. The Sign-in security page is the intended onboarding step, not a deployment error.

Super admins, admins and employees have mandatory MFA. IT administration also requires it. An employer can configure its general MFA policy, while financial workspaces keep their sensitive-session checks.

## Set up an authenticator from a desktop or phone

1. In **Sign-in security → Authenticator**, enter the password used for this Lightek account. Choose **Set up authenticator**.
2. The next page displays a **Setup key**. In your authenticator app, add an account manually using that key. Label it with your Lightek email address so you can identify the right code later.
3. Choose **time-based / TOTP**, **six digits**, **30 seconds**, and **SHA-1** if the app asks for those settings.
4. Alternatively, choose **Open in authenticator** on a device with a compatible app registered for `otpauth://` links. On a desktop without that handler, add the setup key manually in the authenticator on your phone. The current setup page supplies a key and link, not a QR code.
5. Back in Lightek, enter the current six-digit code and choose **Verify & enable**. Enrollment must finish within ten minutes.
6. Save the **ten recovery codes** in private storage you can access if the authenticator device is lost. Each works once; the clear-text list is shown only at enrollment.
7. Choose **Continue to security settings**, then open the intended Dashboard workspace. If enrollment started during a Connect handoff, choose **Continue to connected management** instead.

Do not share the setup key, password, verification codes or recovery codes in chat, tickets or screenshots. Lightek does not need you to send those to support to explain this screen.

## What the organization sign-in section means

**Link organization sign-in** is separate from authenticator enrollment. Leave it alone unless the company's IT administrator has configured an OIDC provider under **Directory & Access → Organization sign-in** and supplied its organization code.

The organization code identifies that configured connection. It is not your authenticator code or a request to invent a new organization. Linking requires a signed-in local account, its password and the configured provider flow. A matching email address alone cannot link accounts. Local authenticator verification remains independent of the provider.

## Subsequent sign-in

Enter the usual email and password, then the authenticator code at **Verify your sign-in**. An unused recovery code is accepted on that same challenge screen. A pending challenge lasts five minutes; start a new sign-in if it expires.

Verified MFA sessions have a twelve-hour freshness window. Ordinary session/device handling still applies. Sensitive features can ask for verification again when that window expires. Password authentication alone does not mark a session MFA-verified.

## If a code is rejected

- Confirm you are using the entry for this Lightek account and instance.
- Let a used or nearly expired code roll over, then enter the new code. Successful codes cannot be replayed.
- Set the authenticator device's date/time automatically; time-based codes depend on its clock. A server clock issue needs an operator to check the host.
- If the setup page is over ten minutes old, restart enrollment from Sign-in security and use the newly displayed key.
- For a stale login challenge, choose **Start a new sign-in** and repeat the password step.

If verification succeeds but a specific workspace remains unavailable, check its account permissions, feature entitlement and service configuration separately. Completing MFA authenticates the account; it does not appoint an IT administrator or grant access to another employer's books/payroll.

## Lost device and recovery

Use one saved, unused recovery code on the sign-in challenge. Codes are one-time credentials; already consumed codes cannot be reused.

The implemented self-service recovery route is recovery codes. There is no automatic email/SMS factor reset or unauthenticated support bypass. If both the device and all recovery codes are unavailable, report the affected account and the issue through your established operator support channel without submitting secrets. An authorized recovery procedure must be established before changing that account's factor.

Optional accounts can disable their factor only when company/role policy permits it, with the current password and an authenticator/recovery code. Mandatory privileged accounts cannot disable MFA through that control. Security changes invalidate other sessions.

## Agencies opening client Dashboards

WordPress/Shopify Connect links first verify the connected agency account at the central Lightek origin. A valid source session supplies its MFA proof; opening a client from a verified local agency Dashboard can reuse that original direct source. The client's own policy still decides whether to accept delegated MFA.

The pending handoff allows ten minutes for login/enrollment. After approval, redemption is single-use and expires in sixty seconds. Delegated sessions last at most one hour, bounded by source MFA freshness. Connection revocation, source logout, loss of permissions or expiry is checked again on protected requests. Signing out of a local agency Dashboard also ends its retained source; signing out of a remote client ends that client session.

Authenticator management, SSO linking and directory/access-policy changes retain direct sign-in requirements. Both central and client applications need the Connect MFA revision and migration. See [Connect setup and acceptance](../integrations/lightek-connect.md#verified-agency-mfa-handoff).

## Operator reference

The UI routes are `/identity/security` and `/identity/challenge`. Setup, confirmation and disabling are CSRF-protected POST actions. Authenticator secrets use existing Vault encryption, recovery codes are stored as hashes, and code verification is serialized with row locking.

See [enterprise identity and accounting](../enterprise-directory-and-accounting.md) for IT/HR separation, company policy, OIDC setup and directory joining. The current release's combined HTTP acceptance entry point is `test/standalone/enterprise_connect_mfa_checks.rb`; production setup should use the ordinary authenticated UI.
