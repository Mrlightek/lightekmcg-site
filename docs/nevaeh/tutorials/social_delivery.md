# Publish Studio videos to TikTok and Instagram

Studio now uses the existing site's Growth social connections and encrypted SocialVault credentials for **TikTok Direct Post** and **Instagram Reels**. The former Studio placeholder adapters have real HTTP transport, provider references, asynchronous processing and outcome receipts. Credentials never enter the publication form or receipt.

## Set up the connected accounts

1. Connect the site's account in Growth → Connections using the existing OAuth flow.
2. For TikTok Direct Post, enable `LIGHTEK_TIKTOK_DIRECT_POST_ENABLED=1` **after** configuring the developer app for `video.publish`, then reconnect. The default existing OAuth flow continues to request `video.upload` for inbox delivery until Direct Post is enabled. Direct Post requires the additional approved scope; an inbox upload is not a published post.
3. Verify the public video host with TikTok and list the exact host in `LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS`. Each client host used for media needs the corresponding verification/configuration. TikTok unaudited apps remain subject to its private-post restrictions.
4. Instagram uses the existing Facebook Login integration, a connected Instagram professional account, and its required publish permissions. `LIGHTEK_META_GRAPH_VERSION` can select the deployed app's supported Graph version; the default remains the existing `v22.0` integration version.
5. Deploy the updated code, restart workers, and rebuild Studio media for local speech dependencies where needed. Real provider setup and app review are not performed by the tests.

The provider fetches the selected, reviewed video's signed Active Storage URL over HTTPS on the site's saved public host. That URL must be anonymously reachable by the provider; an expired/private network route cannot work. No user-supplied API endpoint or media host is requested by the transport.

## Studio publication form

Open a completed video artifact's **Publish / schedule** action, select TikTok or Instagram Reels, and choose an existing connected account. TikTok loads current creator information and displays that account's name, available privacy choices and duration limit. Select privacy explicitly, choose permitted interaction settings, and disclose paid partnership/own-business promotion and AI-generated content as appropriate. Review the export and authorize the publication using the form checkbox.

The form does not choose TikTok visibility for you. Creator-disabled comments/Duet/Stitch remain disabled. Captions and measured video duration are checked before submission. Existing scheduled publication jobs recheck authorization and provider settings at execution.

## Episode Director delivery

For a completed reviewed episode master:

```text
/produce publish {"production_id":123,"reviewed":true,"artifact_id":999,"destinations":["instagram"],"connections":{"instagram":55},"title":"Family Business — Episode 3","content":"Our latest scene."}
```

TikTok additionally requires the current creator settings, all selected explicitly:

```text
/produce publish {"production_id":123,"reviewed":true,"artifact_id":999,"destinations":["tiktok"],"connections":{"tiktok":54},"title":"Family Business","tiktok_settings":{"privacy_level":"SELF_ONLY","disable_comment":true,"disable_duet":true,"disable_stitch":true,"brand_content_toggle":false,"brand_organic_toggle":true,"is_aigc":true}}
```

Use Studio's form to inspect live creator options first. A full episode may exceed the account's allowed duration; export an appropriate social cut in Studio rather than assuming every destination accepts a long OTT episode. Automatic social cutdowns/cropping remain separate editing work. Facebook Studio video publishing is still unimplemented; the existing Growth Facebook text/link adapter is unchanged.

## Read the actual result

| State | Meaning |
| --- | --- |
| `publishing` | A saved TikTok publish reference or Instagram container is still processing. This is not success. |
| `published` | TikTok reports `PUBLISH_COMPLETE`, or Instagram confirms a published media/container. A TikTok public post ID can arrive after moderation; a private publication is still private. |
| `failed` | A precondition, authorization, processing or provider rejection stopped the workflow. |
| `needs_review` | A non-idempotent provider response was lost, a state is unknown, or bounded polling expired. Reconcile the saved provider reference/account before another submission. |

Instagram processing is checked once per minute for up to five polls; TikTok uses up to 120 one-minute polls to allow longer moderation. Source edits, disconnected accounts and changed permissions are rechecked. Publication receipts expose provider references and sanitized errors, never access/refresh tokens.

Repeated jobs cannot initialize a second submission. A timeout after an upload/init or media-publish request enters reconciliation rather than automatically reposting. A crash after persisting a request claim also blocks resubmission. There is no automatic deletion/undo of an already submitted remote post. Check the provider account when the outcome is uncertain; this first transport does not include a full operator reconciliation screen.

Tests use actual Studio records/MP4 metadata with controlled HTTP responses. They verify request contracts, scope and ownership, no premature success, asynchronous confirmation and duplicate prevention. They do not establish that the production developer apps or accounts are approved or that a live social post was published.

Official contracts checked for this implementation:

- [TikTok Direct Post](https://developers.tiktok.com/doc/content-posting-api-reference-direct-post)
- [TikTok creator information](https://developers.tiktok.com/doc/content-posting-api-reference-query-creator-info)
- [TikTok post status](https://developers.tiktok.com/doc/content-posting-api-reference-get-video-status)
- [Instagram content publishing](https://developers.facebook.com/docs/instagram-platform/content-publishing/)
