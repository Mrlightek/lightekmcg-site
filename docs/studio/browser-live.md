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

A super admin can enter their authorized TikTok RTMP/RTMPS server URL and stream key in **Connect my TikTok destination**. A visible LIVE option or a LIVE Studio download link does not demonstrate external streaming permission. Lightek does not obtain a key through a fabricated API or bypass account access requirements. The existing Content Posting publisher is untouched.

The destination is stored in Lightek Vault at `studio-live-USER_ID-tiktok`, consumer `Studio::Live::Destination`, purpose `live_broadcast`. Destination URLs are restricted to TikTok subdomains and standard RTMP/RTMPS ports. Keys and URLs are not returned to the browser, stored in Studio metadata, or written to FFmpeg/application logs. FFmpeg needs the complete output URL in its server-side process arguments, which privileged server operators can inspect. Test recordings are private files under `tmp/studio_live`, served only through an authorized download action.

After a destination is stored, select TikTok and explicitly confirm **Start TikTok broadcast**. “Sending” is reported only after FFmpeg produces positive output timestamps. It means media is being encoded/sent, not that TikTok has made the broadcast visible. Confirm visibility separately in TikTok. Lightek does not currently set the TikTok broadcast title through an API, moderate chat, or verify viewer delivery. The title here labels the Lightek session.

## Lifecycle and limits

The existing `StudioLiveOperation` records track sessions in a new Studio project, tagged `metadata.broadcaster=browser_v1`, with actor ownership and no raw credentials or media chunks in the database. `Gatekeeper::StudioLivePolicy` applies the explicit human-operated admin/owner policy on reservation, connection, start and heartbeats. This is separate from the Nevaeh automation capability registry; this change grants no automatic live-start capability. Destination configuration is super-admin-only. Super admins can inspect any private recording by ID; regular admins can access only their own.

MediaRecorder produces WebM/VP8+Opus chunks. The browser sends one ordered chunk at a time over the authenticated Action Cable channel and waits for an encoder-write acknowledgement. FFmpeg converts the continuous WebM stream into 720p/24 H.264/AAC. Browser queues are capped at 4 MiB, individual chunks at 1 MiB, server writes time out after five seconds, and missing input stops the encoder after 15 seconds. Two concurrent sessions are allowed server-wide, one per operator. Unexpected disconnection ends the encoder; there is no silent automatic resume or dropped-chunk continuation. TikTok sessions have a two-hour limit. Keep the capture tab active; older browsers may throttle a background canvas.

The broadcast channel suppresses its media/ticket debug logs. The global filters also redact `live_chunk`, `stream_key`, `server_url` and `ticket`. FFmpeg stderr is discarded because it may include the private destination URL. Failures shown to users contain only controlled error messages.

Run `RAILS_ENV=production bundle exec rails studio_live:cleanup` daily using the existing server scheduler and production environment. It removes private test recordings older than 24 hours and marks abandoned sessions failed. Recordings otherwise remain on disk; this PR does not silently install a new scheduler. Session records and projects remain as history.

## Verification

Run `bin/rails test test/services/studio/live_test.rb test/services/studio/live_encoder_test.rb test/channels/studio_broadcast_channel_test.rb test/integration/live_broadcasts_test.rb` in the host test environment. Real encoder checks require FFmpeg and explicitly test media production; a mocked browser check alone is not proof of an actual stream. Live TikTok delivery requires an authorized destination and an operator-confirmed test.

Development verification: 16 service/encoder/Action Cable tests, 73 assertions, passed with Active Record and Action Cable 8.0.4. An actual ActionView-rendered workspace ran in Chromium with synthetic screen/microphone sources and its real MediaRecorder. Its ordered chunks passed through the Ruby/FFmpeg encoder and produced a playable H.264/AAC MP4; audio analysis confirmed silence during holding screen. A separate local RTMP receiver received and decoded actual H.264/AAC output. The browser test used a transport fixture; separate channel tests verified actor-bound tickets, replay isolation and acknowledgements. These checks do not establish native screen permissions on the user's Mac, production Passenger WebSocket routing or live TikTok delivery. Full-host HTTP tests are included for the real checkout.

## Camera and connection follow-up

Enable camera requests video-only browser permission; microphone permission remains separate. Camera only needs no screen sharing permission. Screen + camera adds a camera inset to the shared screen. Choose a camera from the device selector after granting access. Camera changes replace and stop the previous camera track; Disable camera and Release capture stop camera use. No source is transmitted until a session is explicitly started. Camera permission failures are shown without removing an existing screen preview.

The transport now waits for Rails' welcome message before subscribing and offers the standard Action Cable protocol list. Connection failures show the last protocol stage and WebSocket close code. Server logs contain safe subscription/start milestones without ticket or media contents. The supplied production log showed successful WebSocket upgrades and user identification followed by a close; it did not prove a missing Apache module or identify the browser's close cause. This change does not disable origin or authentication checks, and the production close needs verification after deployment. If it persists, capture the stage/code shown in the UI and the Firefox Web Console WebSocket error.
