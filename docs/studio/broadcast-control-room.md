# Studio & broadcasting control room

Open **Settings → Studio & broadcasting → Media control room** or `/dashboard/studio-broadcasting`. Choose an application workspace. A platform super admin can select every site's workspace; owners and delegated editors use the existing PWA administration policy.

## Create and release

Use **Open production workspace** to create/edit media with the existing Studio assets, scenes and timelines. Export a master, then select the completed artifact in **Media & releases**. Queue it for Lightek Social, Lightek Streaming or Octavia. Optional release times use the displayed Rails application timezone. Delivery runs through the existing Studio publication worker and Gatekeeper authorization, with visible published/failed/cancelled states. Cancelling a queued publication and concurrent delivery claims are serialized. Hiding a catalog title removes it from ordinary viewer catalogs and the protected PWA media endpoints. Administration previews retain their existing super-admin privileges.

## OTT applications

Create a named app with a stable app key and platform (Roku, Fire TV, Apple TV, Android TV or web). The existing Gatekeeper paths now serve live records rather than demo programs:

- `/gatekeeper/config?platform=roku&application=octavia`
- `/gatekeeper?platform=roku&application=octavia`
- `/gatekeeper/content/POST_ID?platform=roku&application=octavia`
- `/gatekeeper/screens/live?platform=roku&application=octavia`
- `/gatekeeper/search?platform=roku&application=octavia&q=film`

The site is resolved from the request hostname. App keys never grant cross-site access. When no app key is supplied, Gatekeeper chooses the oldest app for the selected platform. An unconfigured app returns an empty off-air experience; demo playback URLs have been removed. Create and publish the Roku application to activate its catalog.

Controls include app name, minimum client version, availability, accent/background, welcome message, configuration refresh interval, catalog/live/search enablement, captions/autoplay preferences, and all-versus-selected title/channel assignments per app. Changes are picked up when a client refreshes; the server's catalog and content endpoints apply the relevant availability and selection controls. Native players must implement the declared preferences, refresh and minimum-version behavior. This change does not build new OTT binaries or demonstrate behavior on physical televisions.

OTT uses the existing audience/visibility policy and authorized PWA media/HLS endpoints. Public viewers cannot obtain private, hidden, gender-restricted or foreign-site titles. Currently the native VOD contract publishes MP4 masters; live playback uses HLS. No public Active Storage URL bypasses the visibility policy.

## Live production and Restream

**Live Studio** keeps its existing hostname-based PWA site resolution. The media control room opens Live Studio on the selected application’s configured domain. The earlier Live Studio 404 was resolved by correcting the PWA domain configuration; this branch does not change that behavior or include a 404 fix.

Store the Restream encoder URL and stream key in Live Studio's destination form. They remain in Vault and are checked out server-side. The existing RTMP/RTMPS provider validation remains in place. Choose:

- **Lightek** for an audience-authorized native HLS broadcast.
- **Restream** to send the program to the channels enabled in the user's Restream stream.
- **Lightek / OTT + Restream** to generate native HLS and a Restream output from one browser capture.
- **Private test** for a server recording without external publication.

The simulcast encoder supervises both outputs as one session. An output failure fails the session. The UI's sending state reports encoder progress, not confirmation of receipt by TikTok or another external platform. Confirm those destinations in Restream. No external broadcast was started during implementation. Stream keys are never returned to browsers or logged by the encoder.

The dashboard exposes broadcast activity and requests session termination through the existing capture heartbeat. Existing limits remain: two active browser sessions across the server and a two-hour session maximum. The browser must support the existing WebM MediaRecorder capture transport; that compatibility was not expanded in this change.

## Channels and guide

Add a public HTTPS HLS or MP4 source to a channel and set it on air. Draft/off-air channels disappear from Gatekeeper. Each app can select all channels or a subset. Add published OTT titles to non-overlapping guide slots with start/end times. A channel lock serializes simultaneous scheduling changes. The guide is programming metadata; it does not splice VOD files into a continuous feed or run an automatic linear playout service. The configured channel feed supplies actual playback.

## Deployment and verification

Run `bin/rails db:migrate` before serving the new dashboard. The additive migration creates application, channel and guide tables. Existing media, Vault and publication storage remain in use. The new routes precede engine mounts.

Standalone acceptance (Rails 8, no private ecosystem gems required):

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle install
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/broadcast_control_checks.rb
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb
CHROME_PATH=/path/to/chromium node test/javascript/studio_capture_transport_test.cjs
```

The broadcasting checks exercise real HTTP controllers, rendered forms, application/site permissions, CSRF, optimistic locking, publication delivery and cancellation, per-app catalog curation, program guide constraints, Gatekeeper playback contracts, and actual FFmpeg HLS plus FLV outputs. External Restream delivery and physical OTT clients still need live verification with the user's configured accounts/devices. The full production bundle was not booted in the isolated verification runtime.
