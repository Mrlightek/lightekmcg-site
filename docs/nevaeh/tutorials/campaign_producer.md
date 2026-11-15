# Produce a TikTok campaign in Studio

In Nevaeh, choose Operate and say:

> make me a funny tiktok campaign ad promoting Xyzzy service

Nevaeh resolves the current business website (or your only accessible website), creates a draft social campaign and an owned Studio production, then queues a Studio worker. Decide/Reflect only shows the proposed action. If several businesses are available, specify `site_id` with the structured command below.

The native producer builds a 24-second portrait ad with four story beats: hook, setup, introduction and invitation. It saves the timed script, editable storyboard camera/shots, image layers, fades and motion keyframes, on-screen copy and an original instrumental score with editable notes. The worker renders a watermarked 720×1280 MP4 private review preview with FFmpeg. The editable timeline remains 1080×1920 and uses the regular Studio delivery workflow for final exports.

## Supply the business facts and images

```
/campaign {"site_id":123,"service":"Xyzzy service","tone":"funny","description":"Book a video consultation with our team.","audience":"Independent business owners","cta_label":"See appointments","cta_url":"https://example.com/appointments","image_ids":[42]}
```

Only service is required. Tone is `funny` or `professional`. Description/audience are limited to 140 characters, CTA label to 60, service to 80, destination to 1200. Use HTTPS without credentials. Up to four ready image assets from this business may replace generated card backgrounds. Graphics are generated locally; the music is original, with no external generation provider or uploaded third-party track required.

A saved Growth brief is used only when its offering matches the requested service exactly, ignoring case. Its ID/revision and the actual claims are captured in the operation plan. Long brief copy is omitted instead of shortened into a potentially misleading claim. Otherwise the ad is a generic introduction using the service name. Add benefits, audience and destination before publishing. The audience is retained as creative direction; this recipe does not autonomously infer demographic targeting.

This initial producer uses a native, reproducible motion graphics recipe. It does not claim the small neural model invented a unique screenplay, synthesize a voice, animate a 3D cast, or use every Studio feature in every ad. Its scene remains editable in Studio for further recording, image/video replacement, cast, 3D, effects, sound and delivery work. Captions are timed on-screen copy, not a transcript of a nonexistent voiceover.

## Check the result and recover

The action receipt links to the editable Studio timeline and campaign copy, follows the worker status, and adds the private preview link when rendering completes. Studio's Delivery area shows the render operation and its artifacts. Ask:

```
/campaign status 456
/campaign retry 456
```

Use the returned operation ID. Status returns the private preview link after completion and the worker error if it failed. Retry accepts failed productions only. Once composition is saved, retries render that original snapshot without replacing subsequent timeline edits. If the scene was edited before initial assembly, production stops with a stale-edit error; start a new request to keep your edits. A repeated operating request key reuses its action and campaign; it does not create another project.

Permissions are checked at dispatch and again by the worker. Both business marketing access and Studio authoring access are required; operation status and retries remain private to the production owner. Images are scoped to the same business. Revoked access prevents execution and status access.

## Review, export and publish

The private preview is marked `draft_preview` and cannot be attached as publishable campaign media. Review claims and CTA, finish editing, export a full Studio artifact, attach that artifact to the campaign and approve the current campaign content. Schedule or publish through the existing social workflow with the appropriate account connection and consent. Creating this production does not publish to TikTok, create a paid TikTok Ads campaign, spend an ad budget or approve campaign copy.

The Studio queue must be running. Production uses the existing studio-media container and its FFmpeg/fonts runtime; there is no new inference service. Missing render dependencies are reported as failed operations and can be retried after repair.
