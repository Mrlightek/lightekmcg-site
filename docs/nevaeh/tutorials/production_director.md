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

Scene numbers start at one. Each cue supplies actual words; Nevaeh does not read a scene brief aloud as though it were a finished script. The Studio worker synthesizes the line, measures the real WAV duration, creates an owned synthetic-voice asset, and places it with timed on-screen transcript text on the scene's editable timeline. The same worker authorization and stale-edit protections apply at execution.

Stock voice choices are `en`, `en-us`, `en-gb`, and `ar`; speed is 100–220 words per minute. These are local eSpeak NG synthetic voices, not cloned or production-quality actor performances. The Studio media image now includes `espeak-ng`: rebuild/deploy that image to enable the worker. Local development needs `espeak-ng` on PATH or `STUDIO_TTS_BINARY`. Missing engines and failed synthesis produce failed receipts rather than placeholder audio.

Use up to sixteen cues per scene and one hundred per service request. Each line is at most 400 characters and its measured take must fit within both 30 seconds and the scene duration. Long scripts should be broken into scene-sized takes; the conversational message limit remains 4,000 characters. Characters, generated phoneme animation and expression/gesture performance are still handled by Cast/Performance after the appropriate rig and bindings are supplied; voice generation alone does not create lip sync.

## Status, retry and review

```
/produce status 123
/produce retry 456
```

Status takes the **production ID**. Retry takes a failed **voice operation ID**, listed in the receipt. Nevaeh follows pending voice jobs and links to the episode in Studio. Replaying the same operating request returns the same episode; reusing its request key with different inputs is rejected. Voice job replays cannot duplicate completed assets or captions. If someone edited a scene while synthesis was running, the worker stops instead of replacing those edits.

`prepared` means the episode workspace and requested voice assets are ready for further work. `needs_attention` means a voice job failed. Neither status means the complete show was rendered or published. The readiness receipt explicitly identifies unfinished cast/performance work, an unrendered episode master, and unpublished deliveries.

The destination list uses the existing publisher keys (`tiktok`, `instagram`, `facebook`, `lightek_social`, `lightek_streaming`/`octavia`). It records portrait or landscape delivery needs. It does not automatically crop finished footage, stitch all scenes into a long-form master, schedule social posts, or publish an OTT title. Those still use Studio's render, edit, review and publishing workflows; automatic full-episode assembly and performance orchestration remain further integration work.
