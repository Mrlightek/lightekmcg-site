# Browser Live Studio

Open **Settings → Studio & broadcasting → Live Studio**, or `/dashboard/live`.
Use a browser supporting camera capture, canvas capture and WebM MediaRecorder (and screen capture when sharing a screen) (Firefox or Chrome). HTTPS and macOS screen-recording/microphone permissions are required. No TikTok desktop application, extension or Mac-side encoder is needed. Test on the actual older Mac before broadcasting; browser version support and available CPU still matter.

## First private test

1. On the Ubuntu Passenger application server, run `bash lib/scripts/install_lightek_live_encoder.sh` as root. This installs FFmpeg if missing, then verifies H.264/AAC support. It changes no application settings or running containers.
2. Deploy the application normally. No migration, new gem or Node service is required. The existing Rails `/cable` connection authenticates signed session cookies; the production Redis connection must be running.
3. Open Live Studio, enable the camera or choose a screen/window, enable the microphone and review the preview. Choose Camera only, Screen only, or Screen + camera. Select **Private test recording** and start it.
4. Try holding screen and resume. Holding screen replaces both video sources and mutes the microphone. Ending a video source used by the selected layout activates holding screen automatically. It cannot automatically recognize or redact credentials inside an actively shared window.
5. Stop the session. Download the private MP4 recording and check that video and microphone play correctly. Private test sessions stop automatically after two minutes. No media is sent to TikTok for this test.

If the connection cannot start, confirm Passenger/reverse-proxy WebSocket support for `/cable`, the authenticated session and the FFmpeg install. `RAILS_ENV=production bundle exec rails studio_live:doctor` verifies the server encoder but is not a browser or platform delivery test. Rails production logs are written to STDOUT and appear in the configured Passenger/Apache log.

## TikTok destination

A super admin can enter their authorized TikTok RTMP/RTMPS server URL and stream key in **Connect TikTok directly with a TikTok stream key**. A visible LIVE option or a LIVE Studio download link does not demonstrate external streaming permission. Lightek does not obtain a key through a fabricated API or bypass account access requirements. The existing Content Posting publisher is untouched.

The destination is stored in Lightek Vault at `studio-live-USER_ID-tiktok`, consumer `Studio::Live::Destination`, purpose `live_broadcast`. Destination URLs are restricted to TikTok subdomains and standard RTMP/RTMPS ports. Keys and URLs are not returned to the browser, stored in Studio metadata, or written to FFmpeg/application logs. FFmpeg needs the complete output URL in its server-side process arguments, which privileged server operators can inspect. Test recordings are private files under `tmp/studio_live`, served only through an authorized download action.

After a destination is stored, select TikTok and explicitly confirm **Start TikTok broadcast**. “Sending” is reported only after FFmpeg produces positive output timestamps. It means media is being encoded/sent, not that TikTok has made the broadcast visible. Confirm visibility separately in TikTok. Lightek does not currently set the TikTok broadcast title through an API, moderate chat, or verify viewer delivery. The title here labels the Lightek session.

## TikTok through Restream

This route keeps camera, screen, microphone, holding screen and encoding inside Lightek. Restream relays the server feed to the TikTok account authorized in Restream; no Mac-side streaming software is required.

1. In [Restream](https://app.restream.io/), open Channels → Add New → TikTok Live and authorize TikTok. This still requires a successful TikTok login and approval. Native mobile LIVE access does not guarantee access through Restream. Restream currently documents a 50% gaming-content requirement; verify eligibility for non-gaming build streams before buying anything.
2. Create New Stream → Encoder | RTMP. Enable the authorized TikTok channel and disable unintended channels. Set the public title in Restream; the Lightek title labels the local session only.
3. Choose RTMPS when available and copy **Restream’s** server URL and stream key, not the TikTok developer client key/secret.
4. As the same Lightek super admin who will broadcast, open Live Studio → Connect TikTok through Restream. Save the URL/key in Vault. Both fields are blank on subsequent page loads.
5. Choose TikTok LIVE via Restream, review camera/mic/holding screen, and confirm Broadcast via Restream. Restream may immediately distribute to every enabled channel for that encoder stream.
6. Verify video and sound in Restream and check TikTok from another device. “Sending to Restream” confirms encoder output only. Saving a destination cannot establish that TikTok is authorized or public.
7. Stop in Lightek and confirm that the broadcast has ended in Restream/TikTok. Reuse the same Restream stream card or update the saved credentials if Restream generates/resets a key.

The relay has a separate per-operator Vault slug `studio-live-USER_ID-restream` with the existing consumer/purpose policy. TikTok direct credentials remain under their original slug. Session metadata records `destination=restream`, with platform `tiktok` and a credential reference; it contains no URLs or keys. Provider selection flows from the authorized operation into the channel’s Vault checkout at encoder start. Only `*.restream.io` RTMP/RTMPS destinations on ports 1935/443 are accepted. An arbitrary relay URL, IP address, or TikTok URL in a Restream configuration is rejected. The existing actor, capacity, CSRF, owner and recording checks remain in force.

Deploy normally; there are no schema, gem, systemd or Apache changes in the relay update. The installed Cable service must be running. No Restream developer application credentials are needed for this encoder setup. Lightek does not implement Restream OAuth or claim account approval: the operator authorizes TikTok directly in Restream.

Provider references checked October 26, 2026:

- [Connect TikTok and eligibility](https://support.restream.io/en/articles/6721574-stream-to-tiktok)
- [Encoder setup and stream keys](https://support.restream.io/en/articles/6505602-go-live-with-streaming-software)
- [Encrypted RTMPS setup](https://support.restream.io/en/articles/8523770-encrypt-your-stream-with-rtmps)
- [Restream network domains/ports](https://support.restream.io/en/articles/4301471-optimise-your-network-settings)

## Lifecycle and limits

The existing `StudioLiveOperation` records track sessions in a new Studio project, tagged `metadata.broadcaster=browser_v1`, with actor ownership and no raw credentials or media chunks in the database. `Gatekeeper::StudioLivePolicy` applies the explicit human-operated admin/owner policy on reservation, connection, start and heartbeats. This is separate from the Nevaeh automation capability registry; this change grants no automatic live-start capability. Destination configuration is super-admin-only. Super admins can inspect any private recording by ID; regular admins can access only their own.

MediaRecorder produces WebM/VP8+Opus chunks. The browser sends one ordered chunk at a time over the authenticated Action Cable channel and waits for an encoder-write acknowledgement. FFmpeg converts the continuous WebM stream into 720p/24 H.264/AAC. Browser queues are capped at 4 MiB and recorder bursts are split into 256 KiB transport chunks (the server accepts up to 1 MiB per chunk), server writes time out after five seconds, and missing input stops the encoder after 15 seconds. Two concurrent sessions are allowed server-wide, one per operator. Unexpected disconnection ends the encoder; there is no silent automatic resume or dropped-chunk continuation. External broadcast sessions have a two-hour limit. Keep the capture tab active; older browsers may throttle a background canvas.

The broadcast channel suppresses its media/ticket debug logs. The global filters also redact `live_chunk`, `stream_key`, `server_url` and `ticket`. FFmpeg stderr is discarded because it may include the private destination URL. Failures shown to users contain only controlled error messages.

Run `RAILS_ENV=production bundle exec rails studio_live:cleanup` daily using the existing server scheduler and production environment. It removes private test recordings older than 24 hours and marks abandoned sessions failed. Recordings otherwise remain on disk; this PR does not silently install a new scheduler. Session records and projects remain as history.

## Verification

Run `bin/rails test test/services/studio/live_test.rb test/services/studio/live_encoder_test.rb test/services/studio/live_destination_test.rb test/channels/studio_broadcast_channel_test.rb test/integration/live_broadcasts_test.rb` in the host test environment. Real encoder checks require FFmpeg and explicitly test media production; a mocked browser check alone is not proof of an actual stream. Live TikTok delivery requires an authorized destination and an operator-confirmed test.

Development verification: 16 service/encoder/Action Cable tests, 73 assertions, passed with Active Record and Action Cable 8.0.4. An actual ActionView-rendered workspace ran in Chromium with synthetic screen/microphone sources and its real MediaRecorder. Its ordered chunks passed through the Ruby/FFmpeg encoder and produced a playable H.264/AAC MP4; audio analysis confirmed silence during holding screen. A separate local RTMP receiver received and decoded actual H.264/AAC output. The browser test used a transport fixture; separate channel tests verified actor-bound tickets, replay isolation and acknowledgements. These checks do not establish native screen permissions on the user's Mac, production Passenger WebSocket routing or live TikTok delivery. Full-host HTTP tests are included for the real checkout.

## Camera and connection follow-up

Enable camera requests video-only browser permission; microphone permission remains separate. Camera only needs no screen sharing permission. Screen + camera adds a camera inset to the shared screen. Choose a camera from the device selector after granting access. Camera changes replace and stop the previous camera track; Disable camera and Release capture stop camera use. No source is transmitted until a session is explicitly started. Camera permission failures are shown without removing an existing screen preview.

The transport now waits for Rails' welcome message before subscribing and offers the standard Action Cable protocol list. Connection failures show the last protocol stage and WebSocket close code. Server logs contain safe subscription/start milestones without ticket or media contents. The supplied production log showed successful WebSocket upgrades and user identification followed by a close; it did not prove a missing Apache module or identify the browser's close cause. This change does not disable origin or authentication checks, and the production close needs verification after deployment. If it persists, capture the stage/code shown in the UI and the Firefox Web Console WebSocket error.
