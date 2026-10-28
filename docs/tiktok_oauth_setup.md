# TikTok OAuth setup in Lightek

1. Register a TikTok developer app, configure Login Kit authorization and request the video.upload scope; get app approval for the intended scopes.
2. Register the exact callback URL: https://YOUR-LIGHTEK-HOST/dashboard/agency/social/tiktok/callback
3. In Dymond Dash > Vault, store the app secret as slug `lightek-tiktok-oauth-app`, provider `tiktok`, purpose `social_oauth`, with payload fields `client_key` and `client_secret`. Allowed consumer: `lightek_marketing`. Allowed purpose: `social_oauth`.
4. In Business > Social Publishing, select the site and choose Connect TikTok account. Authorize on TikTok and return to Lightek.
5. The returned access and refresh tokens are stored in Lightek Vault, under the site-specific social credential slug. TikTok inbox submission refreshes expiring tokens ahead of use.
6. Configure `LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS` with exact verified video hosts. A public HTTPS MP4 URL is required on the campaign media URL.

This integration supports TikTok OAuth and inbox submission. It does not claim public Direct Post or production verification. Verify login, token expiry, callback state validation, scope approvals, and video submission in TikTok test environment before enabling customer deployments.
