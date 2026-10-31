# Lightek PWA acceptance record

Branch: `feature/lightek-pwa-completion-20261031`. No PR or production deployment has been performed. Local results are evidence of the listed paths only; production acceptance remains pending.

## Local evidence

| Area | Verification | Result |
| --- | --- | --- |
| Community audience access | Actual Rails models, workers and HTTP controllers; women/men audiences, private membership, replies, search, attachments, live playlists and segments; gender changes revoke access (including old receipts and mutation replays); legacy HTML/JSON routes use the same policy; super-admin bypass | Passed |
| Top people | Persisted order, Top 5/8 validation, self/duplicate/blocked restrictions, public reads without private gender data | Passed |
| Creator asset library | Actor/site checks and idempotent import through API; protected file downloads; real FFprobe/FFmpeg metadata and thumbnails | Passed |
| Timeline editing | Real multitrack trim, delay, position/volume keyframes, mixed MP4 and PCM WAV exports; owner access; payment-success transition into actual operation job; repeated completed job does not duplicate artifacts | Passed |
| Blender and GLB | Real Blender 4.0.2: `.blend` import, GLB export/re-import, thumbnail render, role-based placement and native scene render with trusted server-resolved asset paths | Passed |
| Native OTT | Real MP4 master publishes into existing posts/attachments with `octavia` distribution and audience policy; nonvideo masters rejected | Passed |
| Native community live | Actual WebM chunks into FFmpeg produce decodable H.264 HLS segments; same audience policy protects catalog, manifest and segment reads | Passed |
| Browser | Actual PWA shell with API fixtures: publish/react, community settings, Top 5, private audience preferences, mobile layout, Studio workspace save/reload, timeline keyframes and asset library | Passed |

The SQLite harness replaces host authentication and private Dispatch at explicit boundaries. It does not verify the deployed ecosystem gems, PostgreSQL behavior, Redis delivery, Docker sandbox operation, Stripe, or real browser screen permissions. The media tests execute native processes; production uses the restricted worker containers instead. The CI workflow installs FFmpeg and Blender and reruns these checks when this feature branch is pushed, without requiring a PR. A separate native-host job uses PostgreSQL, Redis and the existing CI GitHub App credentials to install the private ecosystem gems and run the host Studio/live/social/messaging suite plus Zeitwerk. Neither CI job has run remotely for these unpublished commits.

## Deployment prerequisites

1. Apply all eight `20261031*` migrations. Capability-registration migrations load the existing dynamic seeds; no storefront reseed is necessary. Restart Rails, Sidekiq and the standalone Action Cable backend.
2. The deployment Sidekiq service now consumes `studio` in addition to `default` and `mailers`; `config/sidekiq.yml` provides the same queues for ordinary Sidekiq startup. Verify the active process consumes them.
3. Build `docker/studio-media/Dockerfile` on the Ubuntu worker host. Configure `STUDIO_ASSET_WORKER_IMAGE` and `STUDIO_MEDIA_WORKER_IMAGE` to that locally built, versioned image. Uploaded model files and media processing run without network access or application secrets mounted. A working Docker runtime accessible to the job worker is required. `BLENDER_BIN`/`STUDIO_RENDER_ENGINE_BIN` still configure the existing native scene renderer.
4. Configure positive `STUDIO_MEDIA_EDIT_PRICE_CENTS` and the existing `STUDIO_BUILD_SCENE_PRICE_CENTS`. Prices are explicit production configuration. The existing Stripe checkout/callback pipeline handles payment; local tests do not charge anyone.
5. Ensure the configured site host matches incoming HTTPS requests, the reverse proxy accepts intended upload sizes (UI maximum 250 MB), and `/cable` routes to the existing standalone backend. See `docs/studio/cable-server.md`.
6. The Action Cable encoder and Rails web process must share the same application filesystem for protected `tmp/studio_live_hls` files. Multihost deployments require shared private storage or routing to the encoder host; local HLS files are not a CDN implementation. Run `studio_live:cleanup` daily through the existing operations scheduler to remove recordings and ended HLS directories after 24 hours.

## Production acceptance — pending

The current deployment workflow targets `main` on the live Passenger host. It is not a staging workflow. Do not invoke it as a shortcut for testing an unpublished feature branch.

After an approved verification deployment, run with the host application's configured environment:

```sh
RAILS_ENV=production LIGHTEK_VERIFY_HOST=lightekmcg.com bundle exec rails lightek_pwa:verify_infrastructure
```

The task checks PostgreSQL/migrations, registered capabilities, site mapping, Redis, active Sidekiq queues, Active Storage read/write/delete, pricing, server FFmpeg, and actual isolated media-worker encoding/model preview. It prints check names and error classes without credentials. Passing it is necessary but does not replace the remaining acceptance journeys:

- Run the host's targeted Rails tests for Studio, live, social and messaging against PostgreSQL, with the private ecosystem dependencies installed, plus `zeitwerk:check`.
- Use dedicated women, men, unspecified and super-admin test accounts over HTTPS. Verify women-only Nail Salon and men-only Barbershop communities, invitation-only membership, restricted posts inside general communities, replies/search/media/chat, profile changes and direct-link attempts. The gender setting is private and self-declared; it is not identity verification. Existing private membership/invitation controls remain available.
- Upload real creator image/audio/video/Blender/GLB samples through the deployed browser, await Sidekiq ingestion, preview/place assets, save/reload timeline edits and export through Stripe test mode. Verify signed payment callbacks and job completion without duplicate artifacts. Use the test payment environment, not live charges.
- Publish an exported video to native Lightek Streaming/Octavia. Check catalog and playback using both permitted and denied accounts. Verify scheduled publication is actually delivered by the existing job runner.
- Broadcast camera/screen/microphone to a community through the real `/cable` transport; watch HLS from another authenticated session; verify audience revocation and ended-stream cleanup. External platform delivery requires separately configured authorized destinations.
- Install the PWA on a target mobile browser, confirm the updated offline shell, and verify sign-out/another-account behavior without cached private API content.

Keep the PR unopened until these results are recorded against the deployed commit. No production acceptance result is claimed in this branch.
