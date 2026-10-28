# Meta publishing connections

Register a Meta app with Facebook Login, enable the needed Pages/Instagram publishing permissions and complete any required app review. Add the exact redirect URL `https://YOUR-HOST/dashboard/agency/social/meta/callback`.

Store an app secret in Lightek Vault under slug `lightek-meta-oauth-app`: payload keys `app_id` and `app_secret`, purpose `social_oauth`, allowed consumer `lightek_marketing`, allowed purpose `social_oauth`.

From Dymond Dash > Business > Social Publishing, connect Facebook and Instagram. The callback obtains a long-lived user token, discovers available Page tokens and Instagram professional accounts, and stores publishing tokens in site-specific Vault secrets. Disconnecting revokes the local Vault secret, but does not remotely revoke Meta permissions; users can revoke the app in Meta settings.

Page token validity and revoked permissions must be rechecked against Meta before publishing; reconnect when access expires or permissions change. A token refresh/rotation mechanism for Meta Page tokens is not established in this PR. Verify scopes, app review, connection, post creation and disconnected status with Meta test accounts before enabling production.
