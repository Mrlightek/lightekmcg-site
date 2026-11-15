# Direct episodes with existing Studio recipes

Nevaeh reuses Studio's recovered show bibles, production presets, native Blender compiler, camera coverage, production blueprints, and the Screenplay Engine speech synthesizer. It does not replace those libraries with an unrelated four-card ad template.

In Operate, say:

> make a 22 minute comedy episode called Family Business

Other built-in phrases select a 42-minute procedural or a 48-minute drama. `/produce catalog` lists the available production templates and show bibles. The duration belongs to the selected recipe: an episode consists of multiple scenes, each with its own editable timeline. The ten-minute editing limit applies to an individual timeline, not the sum of a show's scenes.

## Select the recipe, bible and delivery destinations

```
/produce {"site_id":123,"name":"Family Business — episode 3","template_key":"comedy","show_bible_key":"base/show_bible","episode_number":3,"destinations":["lightek_streaming","tiktok","instagram"]}
```

`template_key` accepts an exact key from the catalog or the aliases `comedy`, `procedural`, `drama`, and `documentary`. The existing library includes original 22-, 30-, 42- and 48-minute formats as well as shorter starter productions. A separate show bible is optional; its resolved definition and source checksums are saved with the production, and its guidance is visible in each scene's Script workspace.

The actual preset compiler creates scene geometry, lights and cameras. The Director turns the template's saved coverage into editable storyboard shots using those camera objects. Existing segment briefs, music cues, performance cues and native Blender camera cuts remain available. This is automatic template-based staging and camera direction, using editable blocking sets/performers where the template specifies placeholders. It does not turn those placeholders into finished animated actors.

The production records the source recipe/bible, episode number, department blueprint, task dependencies, scene order and planned runtime. Dependency groups describe remaining work; creating them does not claim those jobs have all executed. Each new episode owns independent scenes, so it cannot overwrite a previously edited episode.

## Automatic stock voices from supplied dialogue

Include dialogue cues when creating the production:

```
/produce {"site_id":123,"name":"Family Business — voice test","template_key":"comedy","dialogue":[{"scene":1,"speaker":"Host","text":"Welcome to Family Business.","start":0,"voice":"en-us","speed":155}],"destinations":["lightek_streaming"]}
```

Scene numbers start at one. When a cue omits `start`, the voice worker places it after the preceding measured take; explicit start times are retained. Each cue supplies actual words; Nevaeh does not read a scene brief aloud as though it were a finished script. The Studio worker synthesizes the line, measures the real WAV duration, creates an owned synthetic-voice asset, and places it with timed on-screen transcript text on the scene's editable timeline. The same worker authorization and stale-edit protections apply at execution.

Stock voice choices are `en`, `en-us`, `en-gb`, and `ar`; speed is 100–220 words per minute. These are local eSpeak NG synthetic voices, not cloned or production-quality actor performances. The Studio media image now includes `espeak-ng`: rebuild/deploy that image to enable the worker. Local development needs `espeak-ng` on PATH or `STUDIO_TTS_BINARY`. Missing engines and failed synthesis produce failed receipts rather than placeholder audio.

Use up to sixteen cues per scene and one hundred per service request. Each line is at most 400 characters and its measured take must fit within both 30 seconds and the scene duration. Long scripts should be broken into scene-sized takes; the conversational message limit remains 4,000 characters. Register a rig and its facial/bone bindings in Cast before using automatic character direction below. Voice generation by itself does not create a character.

## Status, retry and review

```
/produce status 123
/produce retry 456
```

Status takes the **production ID**. Retry takes a failed **voice operation ID**, listed in the receipt. Nevaeh follows pending voice jobs and links to the episode in Studio. Replaying the same operating request returns the same episode; reusing its request key with different inputs is rejected. Voice job replays cannot duplicate completed assets or captions. If someone edited a scene while synthesis was running, the worker stops instead of replacing those edits.

`prepared` means the episode workspace and requested voice assets are ready for further work. `needs_attention` means a voice job failed. Neither status means the complete show was rendered or published. The readiness receipt includes voice jobs, render quotes, assembly jobs, and actual per-destination publication outcomes. Read each stage separately; preparation and submission do not mean publication.

The destination list uses the existing publisher keys (`tiktok`, `instagram`, `facebook`, `lightek_social`, `lightek_streaming`/`octavia`). It records portrait or landscape delivery needs. Automatic native finishing is described below. Social cropping/cutdowns still use the editing tools; TikTok Direct Post and Instagram Reels now have connected transports described in [Social Delivery](social_delivery.md); Facebook Studio video transport remains unavailable. No external publication success is fabricated.


## Direct a supplied character automatically

After a dialogue job completes, supply its operation ID, zero-based cue index, a ready Cast asset, and the scene's current lock version:

```text
/produce animate {"production_id":123,"scene_id":456,"cast_asset_id":789,"voice_operation_id":321,"cue_index":0,"lock_version":2}
```

The Director places that owned Cast asset, binds its generated dialogue audio, measures a real mouth envelope, and saves editable mouth animation plus a small head nod/brow expression when those controls are available. Optional `motion_clips` use the existing Body Motion schema and only that character's registered actions. Missing bindings are not guessed. The initial automatic lip sync is volume-driven, not phoneme recognition. A character supports up to 32 successive, non-overlapping performance takes in the same scene. Repeating `/produce animate` for another cue reuses the pinned Cast object and appends its recording. Speaker and listener attention cues follow the saved take times. Overlapping takes for the same character are rejected; manual replacement requires explicitly clearing the sequence in Performance. The result remains editable and needs artistic review; source actors, a complete screenplay, and high-quality performances are not generated by this command.

## Render the episode scenes

```text
/produce render 123
```

This creates full-scene Blender movie snapshots and the existing render quotes, with a checkout link in the receipt. Complete checkout in Studio Delivery; the existing payment webhook queues the render worker. Request replays retain the same snapshots; changed scenes require a new request. It does not authorize a charge or bypass render payment. Full-scene rendering accepts 1–2400 frames per scene; split longer scenes first. These are native scene renders, including bound character dialogue; mix unbound voice tracks, graphics, music and finishing edits through Studio's timeline/video editor and export those full scene edits when needed.

## Assemble a full episode master

```text
/produce assemble 123
```

Nevaeh selects the newest completed full video export matching each scene's current revision in the recipe's saved scene order. Missing scenes block assembly. To choose explicit exports:

```text
/produce assemble {"production_id":123,"scene_artifact_ids":[901,902,903]}
```

Choose exactly one complete scene export per scene. Supported sources are current Blender movie renders, Studio FFmpeg timeline exports, and Video Studio exports. Individual storyboard shots and draft previews are rejected; edit shots together and export the full scene first. Each video must match the saved scene duration within 0.15 seconds. The worker pins source blobs, verifies edits again before completion, preserves credits, normalizes to 1920×1080/24fps H.264 with stereo 48kHz AAC, and concatenates a private MP4 with a verified runtime. Footage is fitted with padding rather than cropped. The receipt links the master for review.

Limits: 100 scenes, ten minutes per scene, four hours and 10 GB of source exports per episode. The episode is not forced into one ten-minute timeline. Stale edits, missing media, cancellation and processing errors stop the job without a successful master. Rendering longer shows still depends on adequate worker storage and compute. If assembly fails, correct the error and submit a new assembly request; a replay of the same request returns its existing job.

## Publish the reviewed master to community and OTT

```text
/produce publish {"production_id":123,"reviewed":true,"artifact_id":999,"destinations":["lightek_streaming","lightek_social"],"title":"Family Business — Episode 3","content":"Our latest episode."}
```

`artifact_id` must be a completed Director episode master for this production, and its scenes must still match the assembled revision. `reviewed:true` is an explicit instruction to deliver the reviewed master. Native destinations are `lightek_social`, `lightek_streaming`, and `octavia`. TikTok and Instagram require connected-account inputs described in [Social Delivery](social_delivery.md). Optional audience rules use the existing community publisher. Permissions and scene revision are rechecked at dispatch. Repeated delivery requests reuse records; changed input under the same request key is rejected. Actual publisher failures remain failed and visible. TikTok and Instagram use scoped connections and explicit provider settings; see the Social Delivery guide. Facebook Studio video transport remains unavailable.

Use `/produce status 123` to inspect jobs, master artifact IDs, checkout/review links, and each publication's real status. The first episode prompt prepares the production; character direction, paid rendering, assembly and reviewed delivery are now connected commands, rather than a claim that every show is finished from one sentence.


## Collaborative story and spatial direction

The optional zodiac/birth-inspired fiction templates, four-stage worker pipeline, character knowledge/viewpoints, pinned Cast identities across a `series_key`, relative cameras/gaze, personal space, frame-sampled collision checks and focal depth are documented in [Characters & Story Simulation](story_simulation.md). `/produce personalities` opens the catalog; `/produce story {…}` starts the shared worker pipeline; `/produce blocking {…}` saves explicit spatial direction.

These are authored, editable production workflows. A complete screenplay, final artistic acting, automatic obstacle avoidance and one-prompt finished long-form production are not claimed.

Use the [graphical Director stage](director_stage.md) to keep the conversation, script, saved blocking, embedded 3D tools, worker receipts and rehearsal video together.
