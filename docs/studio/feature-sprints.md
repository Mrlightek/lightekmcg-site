# Studio feature sprints

Implementation continues in feature sprints, with focused checks as code lands. The integrated verification sprint runs after the agreed feature scope has been implemented. It covers the whole production and distribution workflow and supplies the launch go/no-go decision.

## Implemented foundations

- [x] Photo/video editing engines, saved projects and PNG/MP4 exports.
- [x] Bounded CPU economy scene rendering, saved-frame integrity/recovery, resource-slot deferral and measured job progress; neural-engine installation restricted to infrastructure operators. See [CPU economy](cpu-economy.md).
- [x] Dedicated CPU worker queue within one installation, tenant concurrency caps, fenced expiring attempts, interruption reconciliation and shared-filesystem checkpoint handoff. See [Shared CPU workers](shared-cpu-workers.md).
- [x] Saved Blender authoring commands and an interactive object-skew control (PR #241).
- [x] Named Blender modifier stacks, typed parameter controls, independent viewport/render state, ordering/removal and saved undo/redo. See [Modifier stack](blender-modifier-stack.md).
- [x] Ordered storyboard, camera/frame/Cast selection and immutable shot render snapshots.
- [x] Managed Genesis worker/model setup, authenticated routing, resumable verified packages and core image/video recipe contracts. See [Genesis workers](genesis-workers.md).
- [x] Offline speech-driven mouth cues, editable phoneme takes, optional detailed face bindings and native Blender animation. See [Character lip sync](character-lip-sync.md).
- [x] Source-bound body-motion clips, trim/speed/repeat/layer/blend controls, saved arrangements and editable native NLA playback. See [Body motion clips](body-motion-clips.md).
- [x] Per-slot native/Cast material controls, sparse input overrides and a reversible scene compositor finish. See [Look & materials](look-and-materials.md).
- [x] Instrument performance capture from screen/computer/MIDI input, review/quantization and existing note-source handoff. See [Performance recording](music-performance.md).
- [x] Music-clock-driven muted picture monitor, saved scoring cues/start and aligned mix replacement. See [Picture scoring](music-picture-scoring.md).
- [x] Song-clock microphone overdub, bounded full passes or selected-bar punch-in/out, discarded lead-in, manual timing correction and editable aligned placement. See [Microphone overdub](music-overdub.md).
- [x] Local microphone capture/review, retryable library import and source-bound audio takes through the music mixer. See [Recording & audio takes](music-recording.md).
- [x] Mixer subgroup routing, ordered channel/bus/master EQ/compression/distortion/delay inserts and processed stems. See [Mixer buses & inserts](music-mixer.md).
- [x] Saved EQ/compressor/delay/wet-mix insert envelopes on channels, buses and master, stable insert references and automated delay-tail budgeting (source v8). See [Music automation](music-automation.md).
- [x] Saved bus volume/pan and master volume envelopes, shared live/offline scheduling and processed-stem handoff (source v7). See [Music automation](music-automation.md).
- [x] Saved song automation for gain, pan, filter and delay, with shared live/offline scheduling, bypass and undo. See [Music automation](music-automation.md).
- [x] Reusable multichannel music patterns, linked playlist placements and shared playback/WAV/stem/MIDI expansion. See [Patterns & playlist](music-patterns.md).
- [x] Positioned live graphic overlays with program-pixel sizing, aspect fit, opacity/visibility, versioned production-setup persistence and independent episode reuse. See [Graphic placement](live-overlay-placement.md).
- [x] Operator-selected audience comments in the captured program, source attribution and clear/holding/session cleanup. See [Audience graphics](live-audience-graphics.md).
- [x] Guest program video visibility/order and independent per-participant audio gain, host-only room persistence and holding mute. See [Guest program controls](live-guest-program.md).
- [x] Scene-bound Live Studio setups for prepared stages, imported cameras, subject placement, library media and portable show presentation styling; template/episode copies, room-style restoration, permission revalidation and explicit preview handoff. See [Live production setups](live-production-setups.md).
- [x] Library still → Genesis image-to-video, frozen input review, authenticated worker upload and prepared MP4 handoff. See [Image-to-video](genesis-image-to-video.md).
- [x] Storyboard → Genesis prompt handoff with shot provenance.
- [x] Finished shot → media library → edit handoff and reusable template reference remapping.

These checkboxes record implementation, not completed production acceptance.

## Remaining feature sprints

- [ ] Authenticated CPU worker federation between independent client installations, source/checkpoint transfer without shared filesystems, strict scheduling fairness/compute accounting and measured economical neural-generation runtimes. Dedicated workers currently share one installation’s database, queue and storage.

- [ ] Complete generation recipes for the remaining agreed media types and verify actual inference/output on suitable production hardware.
- [ ] Advanced character creation/performance tools, eligible face/performance models and expanded reusable body-animation controls.
- [ ] Expand direct Blender object/material/rig/compositor controls using the existing documented command contract.
- [ ] Remaining music production: automatic device latency calibration, loop recording and comping, expanded MIDI expression/controllers, expanded instruments/effects and automation recording and additional effect controls; integrated music-to-picture acceptance.
- [ ] Expand saved Live Studio setups into full authored-scene fidelity; complete multi-person composition, stage effects, audience and distribution acceptance.
- [ ] Complete the agreed media publishing and distribution connections across network, streaming, community and social destinations.

## Integrated verification sprint

- [ ] Create a reusable show template and an independent episode.
- [ ] Build/stage cast and sets, direct performances, generate media and render multiple shots.
- [ ] Edit, grade, score, mix and export a complete production.
- [ ] Reopen and revise the production without losing editable sources or references.
- [ ] Reuse its assets/stage in Live Studio and verify real multi-person capture/composition.
- [ ] Verify paid provisioning/worker readiness, normal client access, permissions, quotas and supported devices/browsers.
- [ ] Publish and verify playback/delivery on each agreed destination.
- [ ] Resolve integration failures, then record the go/no-go decision against that scope.
