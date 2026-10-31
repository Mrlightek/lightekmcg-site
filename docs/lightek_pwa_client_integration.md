# Lightek PWA client integration

The PWA is the client-facing Lightek application. Studio is one surface alongside communities, profiles, messages, media, commerce, money, mail and live production.

## Implemented in this branch

- Persisted communities, membership and administration, section ordering and cover images. Women-only/men-only audiences apply to communities and individual posts through the same access policy, including chat, media and live playback. Gender is private and self-declared; super admins retain access.
- Ordered Top 5/8 people integrate with profile Friends sections, with search, reordering and blocked-person checks.
- Account and site-scoped posts, media uploads, replies, reactions, saved posts, events, playlists and series. Private communities, followers-only posts and blocks apply to both feeds and permalink reads.
- Community and watch-party entry points into existing Lightek Messaging. Context access is rechecked when a conversation is read or sent to, including after membership removal.
- Real media feeds, profile content, search and creation replace the sample community/network content. The shell waits for the live renderer rather than briefly showing fixtures.
- Account-scoped Money data and entry points into existing storefront, Marketplace, mail, live and billing workflows. Susu creation uses the existing Rails fallback.
- Creator-scoped Studio projects and scene operations; platform super administrators retain full project authority. Preview channel access observes the same ownership boundary.
- Scene script/storyboard/audio cue/planning documents, layouts and presets save with optimistic locking. Project templates copy the hierarchy and scene elements into independent projects.
- Real camera, light, material and render settings, supported Director scene commands, paid render quotes/checkout, artifact listing and native publication/scheduling. Editor rotations are converted from degrees for Blender.
- The `live` feature can be sold through the existing Marketplace feature-access mechanism. Entitled customers can configure their own destinations and operate their own sessions; ownership still applies.
- Job receipts are polled without repeating mutations. Receipts are restricted to their actor. New mutations use server-derived actor/site/origin, CSRF protection and idempotency keys.
- Private asset ingestion for image/audio/video, Blender and GLB, real thumbnails/model previews, reusable categorized scene placement and trusted asset resolution during rendering.
- A persisted multitrack media timeline with trim, arrangement, position/volume keyframes, browser preview and paid FFmpeg MP4/WAV export through the existing Studio operation pipeline.
- Native Lightek Streaming/Octavia publication into the existing media store and authorized OTT catalog. Community live broadcasts produce protected HLS playback consumed in Watch and community Live.
- Install icons and a versioned offline shell. Private API responses are never cached by the service worker and use `private, no-store`.

## Deployment

Apply the eight new migrations and restart the Rails application and Sidekiq workers. The registration migrations seed the new capabilities; a full reseed of the storefront is unnecessary. The changes are based on `main`, independently of PR #156's provisioning recovery work.

The current request host must match a configured `DymondSite::Site.host`. Existing unassigned Studio projects remain available to platform super administrators. New PWA projects carry their creator and site ownership.

Live access for customers is granted through the existing `UserFeatureEntitlement` flow using the `live` feature. This branch does not change subscription prices or assume that a plan name implies an entitlement.

## Verification

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle install
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/pwa_http_checks.rb
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb
node --test test/javascript/nevaeh-client.test.cjs
python3 test/operations/studio_transform_test.py
NODE_PATH=/path/to/playwright/node_modules node test/javascript/community-browser.cjs
```

The isolated Rails checks execute the production migrations, models, visibility policy, workers, publishers and API controllers against SQLite/Active Storage. Authentication and the private Dispatch queue are replaced only at the HTTP harness boundary. They do not replace a full PostgreSQL/Redis/Sidekiq test of the deployed application. The browser checks use API fixtures to test the actual PWA shell and client contracts. The standalone entry points deliberately do not match Rails' `*_test.rb` discovery pattern.

## Required before the PR

Production verification remains pending. The implementation and local evidence, runtime configuration, and exact deployment acceptance journeys are recorded in [lightek_pwa_acceptance.md](lightek_pwa_acceptance.md). The deployed host has not run this branch's migrations, media worker containers or authenticated/payment/live journeys. No deployment, live charge, external broadcast or PR has been performed.

Existing external social publishing integrations are retained. Director executes its documented bounded scene procedures and escalates unsupported requests through Nevaeh; arbitrary production generation is not claimed.
