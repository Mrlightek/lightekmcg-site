# Lightek session rooms and audience desk

Booking → lobby → admitted voice/video session → Studio program source → existing Lightek community and Restream destinations.

## Booking and room access

Meeting, video, voice, and live resources without an external join URL use built-in rooms. Existing external session URLs retain precedence. Confirmed, paid bookings expose **Enter Lightek session** in My reservations; hosts get **Open session room** in the booking agenda. Separate bookings of the same resource and exact time slot share a room. A reschedule creates a different slot and does not grant access to the old room.

Site owners and super admins control rooms. Guests sign in with their own accounts. Reservations with multiple places can assign their additional places to existing account holders; invitations do not manufacture extra capacity. Hosts open the room and admit waiting guests. They can lock new entries, mute microphones, remove guests, or end the room. Microphone and camera start off. Voice-only tokens allow microphone tracks only. Live audience tokens subscribe and chat but cannot publish media. Studio uses a separate host-only, subscribe-only identity so opening Studio does not kick the host out of their room tab.

Room access opens 15 minutes early and ends at the scheduled finish. Tickets last 45 seconds; no provider administrative grants reach browsers. Hosts ending a room enqueue its media deletion, which disconnects participants. The one-minute reconciliation removes canceled, blocked, or otherwise ineligible participants and retries recently ended-room deletion. Self-hosted LiveKit can refresh connected tokens; short application tickets alone do not revoke existing media connections. Reconciliation and provider removal enforce that boundary. Removing a guest blocks new tickets and rotates the provider room name; a retrying job deletes the retired room. Provider auto-creation is disabled, so old refreshed JWTs cannot recreate a deleted room. Remaining room clients rejoin with devices off after they observe the generation change; Studio must reconnect its source and resume after the temporary holding screen. A provider outage can delay retirement, but does not restore ticket eligibility.

All participants must accept the host-broadcast notice before obtaining a ticket. The room is not automatically recorded or broadcast. The host decides when Studio starts the program output. The reservation guest must be an authenticated account; anonymous public invitation links are not part of this implementation.

## Activate self-hosted media

Dashboard → Reservations → **Activate / manage voice & video rooms** uses a registered installation for the selected website. The reusable job generates a per-site LiveKit credential in Vault and calls the managed server installer over existing Gatekeeper SSH transport. No shared platform media secret is copied into other clients.

The installer creates a pinned LiveKit 1.13.11 Docker service, privately stored JSON configuration, Apache `/rtc/` signaling proxy ahead of any catch-all proxy, and media firewall allowances. It refuses another site's existing media allocation and shared/mismatched Apache virtual-host files. Rails retains its native or container deployment adapter. The service uses the website's existing HTTPS certificate and checks the HTTPS proxy before returning healthy.

Prerequisites are a registered application installation, Ubuntu/Apache with a dedicated active HTTPS virtual host, and at least 2 GB RAM. A 1 GB server fails the memory check before mutation; allocate appropriate media capacity before activation. Allow **TCP 7881**, **UDP 3478**, and **UDP 50000–50100** through provider firewalls as well as the host firewall. The installer does not alter an external provider firewall. This configuration provides TURN/UDP and direct ICE/TCP; TURN/TLS on TCP 443 for restrictive corporate networks requires an additional relay arrangement. Public-network traversal and device combinations must be verified on the chosen host before calling that deployment ready.

This is an explicit Dashboard activation per installation, not an automatic resize or a paid new-server allocation. Client installations first need this application release. Existing registration and fleet-update workflows remain in use.

## Studio production

Keep the participant room open; choose **Bring this session into Live Studio**, then **Connect session source**. Each remote camera/audio track remains independent at the media layer. Studio subscribes, draws the chosen presentation, and mixes remote audio into its existing program stream. Existing library graphics can overlay the program. Holding screen mutes session audio too.

The presentation director includes branded gallery, presenter with sidebar, side-by-side, and featured layouts; title, subtitle, brand colors, scrolling banner, lower thirds, per-person display name/role, crop/fit, mirror, and clean/monochrome/warm/cool/soft camera effects. Save persists the settings on that room. Gallery shows up to 12 visual tiles; presenter mode shows its main subject and up to three sidebar tiles. Audio is mixed from subscribed tracks. Neither tile limits nor a room's capacity are a hardware benchmark.

The composed presentation canvas can be selected as the subject inside an existing prepared Blender/GLB stage. This is a live textured presentation plane in that scene, not separate tracked 3D geometry or automatic AI background segmentation for each guest. Existing camera chroma-key workflows remain. This change does not promise Zoom/Teams feature parity, a full scene editor, native desktop clients, phone dial-in, or server-side conference recording.

Start the same existing Live Studio broadcast to publish one program feed to Lightek, Restream, or both. The working RTMP destinations and Vault stream keys are unchanged.

## Audience return paths

- **Lightek:** signed-in viewers making authorized HLS playlist requests appear for 45 seconds after their last request. The count covers those playback requests, not anonymous viewers, concurrent devices, or external platforms. Visible community post replies appear in the host audience desk using existing community access rules.
- **Restream:** a separately saved `https://chat.restream.io/embed?...` URL displays supported-platform chat in the host desk. This is the read-oriented embed; reply in Restream Chat. Restream does not supply TikTok chat through this path.
- **TikTok-Live-Connector 2.5.0:** enter the live account's `@username` and explicitly connect the direct audience reader. Normalized chat, member arrivals, viewer-count updates, gifts, likes, and social events use an independent Action Cable channel. No official TikTok API key or login cookie is required for public-event reads. The connector uses a third-party signing provider; provider access/rate limits may require a signing key. An optional signing key is stored in Vault, never returned to the browser. Offline, rate-limit, disconnect, and reconnect states are visible. This unofficial upstream can change; a working RTMP stream is not proof that its audience connection succeeded.
- **Social Stream Ninja:** enter the SSN session ID. Enable remote API control plus “Send chat messages to API server” in SSN, then connect the Studio reader. It receives channel 4 events through SSN's documented WebSocket relay. Keep the extension/app and source platform running. SSN is an optional alternate aggregator, not automatically installed on a customer's personal browser.

Social reader output is bounded and normalized to plain text. Chat buffers are ephemeral; raw upstream payloads, cookies, signing keys, and session IDs are not persisted as chat history or logged. Recent named arrivals are observed events, not a full current TikTok viewer roster. Counts from different adapters are not added together because their audiences can overlap.

Production and native installation/update scripts build the pinned Node audience-reader image automatically. Each reader container is read-only, unprivileged, CPU/memory/process bounded, stops after missing heartbeat, and disconnects when the Studio tab leaves. Database leases limit concurrency across Passenger processes (default two readers total, at most one per user/provider); operators can set `LIGHTEK_AUDIENCE_MAX_CONNECTIONS` within 1–32 after sizing the host.

## Release checks

Run migrations and restart Sidekiq and the Cable service after deployment. Added cron reconciliation requires the refreshed schedule. Validate public HTTPS signaling, camera/mic permissions, two real client networks (including relay), host moderation/end, Studio's program picture/audio, and the configured live social account. These are separate from a green isolated acceptance suite. No production changes, real social broadcast, client-server activation, or live TikTok/SSN account verification is performed by opening this PR.

The dedicated CI exercises booking/controller ownership, permission grants, presentation persistence, installer safeguards, normalization, existing capture transport, canvas layouts, and an actual local self-hosted LiveKit multiparty/media/compositor smoke test. The local workspace cannot start LiveKit because its network interfaces are restricted; that media test runs on the Ubuntu CI runner.

References: https://docs.livekit.io/reference/other/roomservice-api/ ; https://docs.livekit.io/transport/self-hosting/deployment/ ; https://github.com/zerodytrash/TikTok-Live-Connector ; https://github.com/steveseguin/social_stream/blob/main/api.md ; https://support.restream.io/en/articles/2388185-read-incoming-chat-messages .
