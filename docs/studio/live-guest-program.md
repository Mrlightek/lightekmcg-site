# Direct guests in the live program

Connect an authorized room in **Live Studio → Guests**, then open **Customize layout & branding** and choose a connected participant under **Style participant**.

- **Show this guest’s video in program** controls whether their camera, shared screen or placeholder appears in the composed output. It does not remove them from the room.
- **Program order · lower first** accepts whole numbers 0–49. Lower values appear first; equal values retain the source order. The gallery shows up to twelve visible items. Presenter layouts retain their existing three-person sidebar, and Interview shows two items. A visible featured guest is promoted into Presenter/Featured output even if their order would otherwise fall beyond the twelve-item cap. Hiding a featured guest keeps them out of the output.
- **Program audio · 0 mute / 1 unity** attenuates that participant’s subscribed audio tracks. The level is linear amplitude: 0.5 halves amplitude. It applies to microphone and shared audio tracks belonging to the same participant. Changes use a short gain smoothing interval.

Video and audio are independent. A hidden or off-layout participant remains audible unless you reduce their program audio to zero. Muting program audio does not hide their video. The controls affect Lightek’s composed program feed, not admission, the participant’s microphone device or what other room participants hear in their own calls.

Names, role labels, visual effects, framing and mirror controls remain available alongside these settings. Hiding a shared screen also removes its influence on automatic gallery-to-presenter selection. Holding screen mutes the entire session mix regardless of individual levels.

## Save and reuse

Edits update the local program preview. **Save this room’s presentation** persists the participant settings through the existing host-authorized endpoint. Guests cannot save them. The server validates visibility, audio range and integer ordering before writing; invalid updates leave the saved presentation unchanged. Legacy room styles default to visible video, unity audio and equal ordering. If an older client edits an included participant without sending these newer fields, the server preserves their saved program controls. Omitting the participant map during a global title/branding update preserves it; explicitly sending an empty map clears it.

**Use this room’s saved presentation** restores the saved room state and refreshes the displayed controls. [Portable show styling](live-production-setups.md) retains the room’s participant controls when applying the show’s title, branding or layout. Production templates do not carry participant identities, visibility or audio settings into other rooms.

Use the explicit audio control for every voice you want excluded from the outgoing program, then review a private test recording.

## Verification

Focused checks exercise host-only persistence, legacy edits, defaults, invalid bounds and unchanged room membership. A native Web Audio test runs the actual session-source gain routing with synthetic source audio to verify per-guest levels, independent video hiding, holding mute and track cleanup. Renderer checks cover ordering, hidden featured guests and the tile cap. The browser capture fixture in CI covers the director controls, explicit save and restoration with simulated room transport. Real participant devices, LiveKit networking and destination playback remain integrated acceptance.
