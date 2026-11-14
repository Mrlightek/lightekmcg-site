# Play and record instruments

Open **Studio → Music → Play & record instruments**. A performance records editable musical notes into an existing instrument channel or reusable pattern. It uses the same Tone.js instrument, channel processing and group/master graph as regular song playback. Microphone waveform recording is available through [Record & place audio takes](music-recording.md) and [Record with song](music-overdub.md).

## Capture a pass

1. Select a musical channel (Keys, Bass, Pad, Lead, a drum sound or an existing sampler). Choose **Song notes** or a reusable pattern as the editing source. Audio-take channels are not pitched performance instruments.
2. Choose the pass length, from one to sixteen bars within that source's length. A pass starts from the beginning and does not loop. The current source plays as backing, including its existing notes and mixer settings. In song mode, an enabled picture monitor follows the same music clock.
3. Choose a note grid: keep timing, quarter, eighth, sixteenth, thirty-second or sixty-fourth. Manual input correction can move captured timing 0–500 ms earlier; it is not automatic device-latency calibration.
4. Click **Record performance**. Hold the on-screen keys or use computer keys **A W S E D F T G Y H U J K** for a chromatic octave plus the next C. Choose the keyboard octave before recording. Typing in text/number fields does not play notes.
5. Click **Finish pass**, or allow the selected number of bars to finish. **Release held notes** clears held keys/pedal state while allowing the pass to continue. Escape finishes a pass when keyboard focus is outside a text control. Losing window focus, hiding the tab, navigating to another production or leaving Music stops the pass and retains completed/held notes for review.
6. Review the completed-note count and choose **Apply editable notes**. Notes are added to the original channel/pattern; matching onsets and pitches are replaced, while other notes remain. Pattern placements update through their existing source links. Use Undo/Redo to reverse or restore application, then **Save music**.

The note grid can be changed during review before Apply or Download; the raw captured timings remain available until the review is discarded. Quantization rounds onset/end and keeps a note inside the pass boundary with at least one grid step (or 1/64 beat when keeping timing). Duplicate quantized onsets/pitches merge with maximum duration/velocity within the captured take. Drum-channel input maps to that channel's drum sound, regardless of incoming key pitch.

**Download performance MIDI** preserves an unapplied take independently. **Discard performance** removes the local review without changing the source. Only one pending performance is retained at a time. A review remains bound to its original production/channel/pattern; if the target was removed, keep/download it rather than losing it on a failed Apply. Local pending performances participate in unsaved-work checks and must be applied/saved or downloaded before closing the page.

## MIDI keyboards

Where `navigator.requestMIDIAccess` is available, click **Connect MIDI keyboard** and grant browser permission, then select an input. Permission is requested only by that action, with System Exclusive disabled. No MIDI output is opened or sent. If the browser has no MIDI input API, use the same on-screen/computer-key workflow.

Incoming note-on/off messages route to the selected musical channel. Velocity-zero note-on is note-off. Note velocity is retained, with the quietest values clamped to the existing source minimum of 0.01. Sustain CC64 is tracked per incoming channel, while All Notes Off/All Sound Off and the release button flush held input. Disconnecting the selected device releases held notes and detaches its listener; leaving Music disconnects the MIDI input. Late/cancelled access or input-open responses cannot reconnect an old selection.

Pitch bend, modulation/expression mapping, program changes, MIDI output, controller automation and external clock synchronization are not implemented in this pass. The screen/computer keys do not require MIDI permission.

## Timing, bounds and monitoring

Capture uses the music transport position and recent browser event timestamps, not animation-frame counts. The pass fixes its tempo, target, correction and bar window while recording; source edits and exports are locked until Finish. Notes held at the end are closed at the pass boundary. MIDI sustain is reflected in both live note release and captured note length.

There are at most 32 held input notes and 4096 captured events. Additional notes skipped at those limits are counted in the review. Existing source limits still apply across all song and pattern notes; if Apply would exceed them or target a missing channel, the edit rolls back and the review is retained. Long passes beyond sixteen bars, count-in/metronome, arbitrary record start positions, loop/punch audio recording, automatic device calibration and advanced expression remain further production work.

The instrument channel's existing mute/solo, processing, automation and bus/master mix remain authoritative for monitoring. Recorded source notes subsequently use regular playback, MIDI interchange, WAV/stem rendering and Add mix to edit. Monitor timing depends on browser/device scheduling; no sample-accurate hardware-latency guarantee is claimed.

## Source and verification

No new composition version or database migration is required. Applied performances are ordinary canonical notes (`beat`, `length`, `pitch`, `velocity`) in an existing track or pattern lane. Existing source versions remain unchanged, including picture-scoring metadata. Template/episode independence and authenticated save-conflict/site boundaries continue through the regular source-save path.

Focused checks cover timestamp/correction/grid conversion, sustain, held-note limits/cleanup, device connection/cancellation/disconnect, computer input, review/apply/undo, song-pattern separation, navigation, cancelled-start races and onset merging. Real Tone.js/Web Audio rendering checks held attack/release across the current synths/drums/sampler, mixer gating and applied-note WAV output. Actual MIDI hardware, browser/device latency and integrated capture-to-picture acceptance remain in the final verification sprint.
