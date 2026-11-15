# Characters, viewpoints and cooperating story workers

The former birth/chart material is now an optional fiction reference in Studio. `/produce personalities` lists **36 creative templates**: twelve zodiac-inspired archetypes with balanced, pressure and growth variations. They supply strengths, tensions and behavioral habits. They are writing prompts, not factual assessments of real people.

Choose a template directly, or supply a fictional character's birth date to select its creative archetype. Optional fictional birth time and place remain attributed character background. These inputs do not change Nevaeh's own permissions or operating decisions.

## One shared narrative state, four real workers

First create an episode with a stable series key:

```text
/produce {"site_id":123,"name":"Family Business — Episode 3","template_key":"comedy","series_key":"family_business","episode_number":3}
```

Then start a bounded simulation for a scene:

```text
/produce story {"production_id":123,"scene_id":456,"characters":[{"id":"amina","name":"Amina","template":"aries:pressure","goal":"protect the workshop","knows":["The door is locked"],"secret":"I hid the key"},{"id":"bilal","name":"Bilal","birth_date":"1990-12-25","goal":"find the missing key","knows":[]}],"events":[{"text":"The spare key is under the desk","visible_to":["amina"]},{"text":"The lights go out","visible_to":["amina","bilal"]}],"viewpoint_cameras":{"amina":1001,"bilal":1002}}
```

Camera IDs must identify actual cameras in that scene. The pipeline creates real `NevaehAgentWorker` and `NevaehAgentRun` records and passes each stage through existing Gatekeeper/Dispatch execution:

| Worker | Saved result |
| --- | --- |
| Sage: characters | Named character briefs, goals, personality prompts and separately retained secrets. |
| Warden: simulation | An event-by-event knowledge and reaction trace for each character, using only events visible to that character. |
| Nevaeh: viewpoints | Scene-local relationships and editable camera coverage associated with character viewpoints. |
| Muse: script | A bounded draft scaffold based on those viewpoints, saved in the existing Script workspace. |

Each worker consumes the earlier stage's saved state. Secret character notes are not silently disclosed to everyone. This simulation tracks authored narrative events and who knows them; it is not an autonomous general world model or a finished screenplay generator. The resulting dialogue is a scaffold for collaborative writing, not a claim of a complete original episode.

```text
/produce story_status 789
```

The returned story operation ID identifies the pipeline. Receipts include real worker/run IDs, stage results, known facts, viewpoint cameras, errors and script draft. Duplicate starts reuse their operation; changed inputs under the same key are rejected. Paused workers, lost permissions, failures and a two-hour deadline stop progression. If the scene changes between workers, the pipeline stops before overwriting the creator's edits. Correct the issue and start a new request; earlier evidence remains available.

## Stable character identity and eyelines

Use a registered, ready Cast asset with the existing `/produce animate` command. Nevaeh pins the asset ID, source blob and rig/profile checksum to the speaker. A different asset cannot silently replace that speaker later in the production. When `series_key` is supplied, the check also compares earlier episodes with that key under the same owner and site.

Automatic placement spaces speakers two metres apart. A two-speaker scene gets reciprocal listener targets; a scene with more speakers requires an explicit `listener_object_id`. Custom characters can supply `facing_axis` (`X`, `Y`, `-X`, `-Y`) to match their rig's forward direction. Root-level facing is automatic. When a head bone is registered, the frame audit also rejects poses more than 30 degrees off the intended listener target. Detailed eye-bone articulation and artistic acting remain rig/Performance work. A source change blocks rendering rather than selecting a replacement face. Identity checks cover this registered 3D Cast path; imported flat generated footage still requires visual review.

## Relative blocking, personal space, collision and depth

```text
/produce blocking {"production_id":123,"scene_id":456,"lock_version":8,"personal_space":0.9,"collision_detection":true,"relationships":[{"object_id":1001,"relative_to":2001,"offset":[0,-5,1.6],"look_at":2002,"look_at_offset":[0,0,1.4],"depth_of_field":true,"aperture_fstop":4},{"object_id":2001,"look_at":2002,"facing_axis":"-Y","personal_space":0.9},{"object_id":2002,"look_at":2001,"facing_axis":"-Y","personal_space":0.9}]}
```

| Field | Meaning |
| --- | --- |
| `relative_to` / `offset` | Optional parent and local offset, like positioning an element relative to another. Moving/rotating/scaling the parent carries the dependent object. |
| `look_at` / `look_at_offset` | A scene-local gaze target and target-local offset, for example a listener's head rather than their feet. |
| `facing_axis` | The character rig's forward axis; cameras use their native negative-Z view axis. |
| `personal_space` | Minimum character-centre distance, in scene metres, from 0 to 5. The larger of the two characters' settings applies. |
| `allow_close_contact` | Set explicitly on **both** characters to permit intended proximity such as a hug. Geometry collision checks still apply. |
| `depth_of_field` / `aperture_fstop` | A perspective camera focused on the tracked target, with an editable aperture. Actual geometry and distance determine depth and parallax. |

Relationships are restricted to objects in the same scene. Relative parenting cycles and missing targets are rejected. Reciprocal speaker gaze uses baked independent targets to avoid circular Blender constraint dependencies. Camera targets follow authored motion across frames. Imported models still need correct dimensions and ground placement; this does not infer real-world scale from an arbitrary mesh.

The Blender renderer checks every integer frame, up to 2400 frames per scene. It checks directed character spacing and evaluated mesh intersections against other characters and scene geometry, including an enclosing solid prop. It allows level floor contact while checking penetration beneath a floor. It does **not** add a rigid-body solver, automatic obstacle avoidance, or continuous subframe collision detection. It detects and stops invalid blocking for correction. Mesh topology and costumes can require manual review; intended intersections can be managed through explicit scene collision settings.

Spatial rules operate on saved 3D characters, sets, positions and cameras. They do not randomize faces, move actors to a new layout during rendering, or treat a blurred flat background as a rebuilt 3D environment.
