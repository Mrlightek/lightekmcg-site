# Publishing calendar and Studio export handoff

## Finish, attach, review, schedule

Open **Publishing** in the shared Business navigation, or **Attach a Studio export / open publishing calendar** from a social campaign's Content review page. Managers/marketers can prepare media and inspect the calendar. Scheduling/canceling a release requires the same admin/super-admin publishing-operator roles used by the existing social publication workspace, plus access to this business website and its marketing feature.

1. Finish a campaign's focused Studio production and export its final image/video. Rendering and editing remain the existing Studio workflows.
2. Select the social campaign in Publishing. Choose a completed full export from an authorized Studio project on this website. Draft previews, unfinished operations and unrelated-site exports are rejected. Supported handoff types are JPEG, PNG and MP4, up to 1 GB.
3. **Attach export for campaign review** retains a separate Active Storage attachment to that exact blob and records artifact/operation IDs, blob ID, checksum, type and size. It updates the campaign's media URL, enrolls it in version-specific content review and returns it to Draft, invalidating prior approval. Repeating the same attachment request reuses the current binding when its file and issuing host match.
4. Review the final copy, media URL, CTA, channel and social format in Content review. Approve a fresh variation set after attaching media. Existing copy approvals remain valid across deployment for campaigns that have not adopted a Studio media binding; the fingerprint gains a binding identity only when one is selected.
5. Choose the reviewed social campaign, connected account, local date/time and timezone. The supported local-time choices are listed explicitly. Missing or repeated local times during clock changes are rejected rather than silently shifted. The window is up to 90 days ahead.
6. **Schedule this reviewed version** records the exact content digest, scheduling operator, connection and time. A repeated request key returns the same slot; different inputs cannot reuse that key. Only one retained, non-canceled slot is allowed per campaign/account. Use another campaign for a different post or cancel an unstarted slot before replacing its time.
7. Inspect the release agenda and existing provider publication records. Publication confirmation is separate from scheduling, queueing and provider submission.

The agenda shows 31 application-timezone dates from the selected start, capped at the first 200 matching slots; each entry also shows its chosen release timezone. The calendar does not pick an allegedly optimal posting time or infer account reputation.

## Adapter scope

| Connected destination | Current calendar behavior |
| --- | --- |
| Facebook | Text/link posting through the existing feed adapter. Media-bearing campaigns are rejected here because that adapter does not upload their image/video. |
| Instagram | Existing JPEG/PNG image publishing through the connected professional account. This does not add Reels or general video publishing. |
| TikTok | MP4 submission through the existing verified-host `video.upload` inbox workflow. The account owner reviews it in TikTok. Submission is not automatic public publication. |

The calendar checks these basic adapter requirements before scheduling and again before execution. Existing OAuth/Vault, account health, media-specific provider limits, permissions and platform approval requirements remain in force. There is no new YouTube, LinkedIn, X, Threads or Reddit adapter in this release.

For TikTok, the actual media entry hostname must be present in `LIGHTEK_TIKTOK_VERIFIED_VIDEO_HOSTS` and verified with the provider using the existing setup. A configured allowlist is not itself proof of verification or successful fetching. Test the real media URL and account before launch.

## Media delivery and revocation

The public entry URL is bound to the **application host that received the Dashboard attachment request**, not necessarily the selected website's host. This keeps exports on the server/database that holds them when a customer website is served elsewhere. The URL contains an opaque random token and a type-appropriate filename. The public controller checks the issuing host, token, filename, tenant marketing feature, revocation state and retained blob identity, then redirects through the existing Active Storage delivery route on that host.

The blob is retained independently of the original artifact attachment. The binding's source metadata, public token and issuing host are immutable. The campaign fingerprint includes the binding's identity when present, and submission also checks that the stored blob ID/checksum still match. This uses the application's immutable-blob/storage integrity contract; it does not re-download/hash a 1 GB file before every provider request.

Attaching explicitly makes this export public through its entry link. **Revoke public media link** blocks new requests to that entry and stops later scheduled submissions from using it. Previously issued storage URLs and downloaded/provider-cached copies may remain usable; revocation is not a recall or proof of removal from social platforms. The entry response is not cached, but downstream storage/provider behavior is separate.

Media delivery can involve redirects to the storage service. Production acceptance must verify that the actual provider follows those redirects and accepts the host/media configuration. This release does not proxy or transcode the bytes into every provider's required delivery format. External media URLs remain supported by existing campaign fields, but have no Studio blob-identity guarantee.

After a campaign acquires delivery/publication history, use a separate campaign for new media or changed approved content. Completed/canceled history and media bindings are retained; complete campaigns instead of deleting their operational evidence.

## Execution, recovery and truthful status

The existing scheduler runs `LightekMarketing::PublicationSweepJob` every minute. It leases enqueue requests for five minutes, so a lost enqueue can be recovered without filling the queue on every tick. Worker execution serializes claims and commits a `dispatching` state plus the SocialPost reference **before** provider IO. Duplicate jobs cannot start another provider request for the same slot.

Before claiming, execution checks the original operator's current role/site access, the marketing feature, connected-account enablement, reviewed payload digest, media availability and adapter scope. SocialDispatch checks the digest, media and operator again under the campaign lock immediately before its existing provider path. Revoking access does not recall a request already in flight.

| Calendar state | Meaning / next action |
| --- | --- |
| Scheduled | Saved, not submitted. Queue-request time is shown when available; it is not a publication receipt. |
| Blocked | Preconditions failed before provider submission began. Fix the reason, cancel the slot and schedule the intended reviewed version again. |
| Dispatching | A durable claim exists; submission is being attempted. Canceling locally is no longer safe. |
| Submitted | A provider reference exists without a public publication confirmation, including TikTok inbox submissions. |
| Published | The existing SocialPost record reports publication. This is a provider-recorded outcome, not a guarantee of future visibility/moderation. |
| Needs review | A response or execution outcome needs reconciliation. Inspect the provider/reference and existing publication tools before any manual retry. |
| Canceled | An unstarted scheduled/blocked slot was canceled locally. This does not cancel a provider request. |

Unknown provider failures are never automatically retried by this calendar. An ambiguous pending SocialPost is also marked Needs review, so the existing manual publication/retry path cannot silently treat it as a fresh pending request. A dispatching claim older than 15 minutes is reconciled against any known receipt, otherwise moved to Needs review. The sweep can advance an entry when the existing TikTok/provider polling record later confirms publication. It does not infer success from elapsed time, silently resubmit unknown requests or mark an inbox upload public.

The publication record remains the provider evidence. The existing manual retry/reconciliation tools retain their own rules; the calendar does not grant additional credential or retry authority. A canceled or blocked slot has no new provider request, while an ambiguous dispatch may already have had an external effect.

## IT operation and deployment

Apply `20261115170000_add_campaign_publishing_calendar` through the per-instance update pipeline. It installs media bindings, publication slots and a campaign media reference. Active Storage, public HTTPS routing, the normal minute scheduler, workers and provider credentials must already be working on that instance. Retain these tables and referenced blobs when reverting code; do not erase provider/history evidence as a recovery shortcut.

Structured events use `lightek.growth.media_attached`, `media_revoked`, `social_scheduled`, `social_canceled`, `social_blocked`, `social_result` and `social_needs_review`. They identify site, actor, campaign, media/artifact or slot IDs and state. They do not log public media tokens, file bytes, copy or Vault credentials. Provider diagnostics continue through the existing publication records and system logs. Database receipts are authoritative.

For a missed release, inspect slot status and queue-request time; confirm the scheduler/worker is running; check the saved operator's current access, campaign digest/approval, connection, media entry and real provider configuration. For a blocked slot, cancel and reschedule after repair. For Needs review, reconcile the external outcome first. Late confirmed receipts can update the calendar without submitting again.

## Acceptance

`ruby test/standalone/publication_calendar_checks.rb` extends the content/Growth/CRM suite with the real migration, calendar/media models and services, routes/controllers, worker claims, sweeps, status reconciliation and actor/version checks. It covers duplicate jobs, lost enqueue recovery, stale copy, revoked access/media, timezone offsets and clock-change ambiguity, issuing-host binding, export scope, blob-identity checks and preservation of preexisting approval digests.

Provider IO, Active Storage attachment/URL delivery and Studio project-policy allocation are boundary fixtures in this standalone host. It does not establish actual storage fetching, a full render, private-engine boot or live social publication. Production acceptance should include a real completed export on the intended instance, provider fetch, scheduled execution and returned provider status.

Export pages with `SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/publication_calendar_checks.rb`, then run `SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs`. Twelve controller-rendered screens are checked at desktop/tablet/phone widths, including the publishing agenda and schedule controls.
