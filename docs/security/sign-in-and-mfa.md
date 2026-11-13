# First sign-in, MFA and recovery

## Why production opens Sign-in security

After the enterprise identity update, privileged platform accounts and accounts covered by an employer MFA policy must enroll an authenticator. A password-only enrollment session cannot open ordinary business workspaces until verification succeeds. The Sign-in security page is the intended onboarding step, not a deployment error.

Super admins, admins and employees have mandatory MFA. IT administration also requires it. An employer can configure its general MFA policy, while financial workspaces keep their sensitive-session checks.

## New clients choose a password first

A new client does not need to know a generated installation password. Self-registration asks them to choose a password. Accounts created on a client's behalf are marked for first-password setup and receive a private account-setup email through the existing mail queue. That link opens a new-password/confirmation form without asking for an old password. It expires after twenty minutes and becomes invalid after a successful password save. Agency administrators can resend a pending client's invitation from the client's own agency row. A queue failure preserves the account and exposes a retry notice.

The purchasing Lightek account and an independently installed application are separate accounts/databases. The ready email includes first-password setup when the purchasing account needs it, followed by **My Applications → Set or reset my password** for the installed application. A deferred installed-owner bootstrap does not email a link before installation is verified. Accounts on deployed client servers still send their own agency-client invitations normally.

After choosing the installed application's password, sign in and complete MFA if required. The MFA screen's **Current password** is then the password just chosen. A password reset invalidates existing sessions but keeps any enrolled authenticator; it cannot bypass an existing MFA challenge. Legacy accounts are not forced into password reset by migration. Their owners can use Forgot password when they have never chosen a password or a link expired.

## Set up an authenticator from a desktop or phone

1. In **Sign-in security → Authenticator**, enter the password used for this Lightek account. Choose **Set up authenticator**.
2. The next page shows a **QR code**. On your phone, open your authenticator and choose **Add account → Scan QR code**. Point the camera at the code on your computer's screen.
3. The authenticator adds the Lightek account and displays a six-digit code. Scanning carries the setup key, time-based mode, six digits and 30-second period automatically. There is no Safari app-opening step on your Mac.
4. If scanning is unavailable, expand **Can’t scan? Enter a setup key manually**. Choose manual entry in the phone app and copy only the **Setup key**, not a website address. Use **time-based / TOTP**, **six digits**, **30 seconds**, and **SHA-1** if requested.
5. Back in Lightek, enter the current six-digit code and choose **Verify & enable**. Enrollment must finish within ten minutes.
6. Save the **ten recovery codes** in private storage you can access if the authenticator device is lost. Choose **Download recovery codes (.txt)** or copy them into your password manager. The download is created locally from the codes on this page; it is not sent to a download service. Each works once; the clear-text list is shown only at enrollment. If your browser cannot download the file, copy the displayed list before leaving.
7. Choose **Continue to security settings**, then open the intended Dashboard workspace. If enrollment started during a Connect handoff, choose **Continue to connected management** instead.

QR generation uses a locally served encoder in your browser; no external QR service receives the secret. If the encoder cannot load, the manual setup section opens with an explanation.

Any signed-in account can open **Settings → Your account → Sign-in security**, or use **Sign-in security** directly in the top-right Settings menu. Clients see personal settings without receiving platform administration permissions. Books & Accounting requires an eligible business and its existing accounting permissions; unavailable workspaces explain the missing access instead of showing an empty page.

Client accounts land on **Your workspace** after sign-in when no explicit return destination was requested. On the agency instance, this shows only their own/delegated websites and their purchased or assigned application installations. Ready applications offer **Launch admin dashboard**, which opens that installation's `/dashboard/` and uses its own sign-in and MFA requirements. The installed application owner remains an admin on that separate instance. **Servers & Applications** remains available as a hosting tool rather than the client's default home.

Do not share the QR code, setup key, password, verification codes or recovery codes in chat, tickets or screenshots. Lightek does not need you to send those to support to explain this screen.

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

See [enterprise identity and accounting](../enterprise-directory-and-accounting.md) for IT/HR separation, company policy, OIDC setup and directory joining. The current release's combined HTTP acceptance entry point is `test/standalone/enterprise_onboarding_checks.rb`; production setup should use the ordinary authenticated UI.
