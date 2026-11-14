# Make music in Lightek Studio

1. Open **Dashboard → Studio → Open studio**, then choose **Music**. You stay in Dashboard and work in the same production.
2. Click **Write a starter rhythm**, or click steps in the drum machine to write your own. Press **Play** to listen and **Loop** to repeat the arrangement.
3. Select **Bass** or **Keys** on the left. Click an empty cell in the piano roll to add a note. Click the note to set its length and strength on the right. **Delete note**, **Undo** and **Redo** keep edits reversible.
4. Choose a bar in **Song arrangement**. **Copy to next bar** and **Repeat through song** copy the selected bar across every instrument. Adjust the number of bars and tempo above the editor. Shortening a song that still contains later notes is rejected so the editor does not silently delete your work.
5. Use the selected track’s **Volume**, **Pan**, **Mute** and **Solo**. Open **Sound shaping** for filtering and delay. Notes and mix controls can update while the arrangement loops. Changing instruments or sample slices stops playback; press Play to resume.
6. To use your own sound, upload it under **Your sample library**. Refresh after preparation, choose **Your audio sample** as the instrument, select the recording and choose the slice and original MIDI pitch. The sample is pitched from that root when you write notes. Sources are limited to two minutes / 25 MB; each slice can be up to 30 seconds.
7. Choose **Save music** to keep the editable source with the production. Under **Import & export**, you can download a WAV mix, the selected track’s WAV stem, or MIDI notes.
8. Choose **Add mix to edit at 0s**. Studio saves the musical source, renders the instruments, prepares the WAV as a media asset and adds it to the episode edit. Return to production and choose **Media edit** to hear it against the picture. Position and trim it like another audio clip. Future bounces update the score’s linked clips, keeping their placement and mix; they do not stack a second copy on top.

**Save show template** copies the production, including this editable music. **Create episode** from that template makes an independent source and scene/edit setup for the next episode.

For an existing project, a concurrent edit in another window is reported when saving. Your draft stays open. Save before leaving the browser; the musical source and undo history are not automatically saved on every click.

This first music workspace supports 4/4 at a constant tempo, up to 16 tracks, 128 bars, ten minutes and 4096 notes. WAV bounces are 48 kHz / 16-bit stereo. MIDI does not include the instrument sounds, sample mappings, effects or swing settings. Recording/comping, hardware MIDI, plugin hosting, automation, expanded instruments, tempo maps and advanced mastering remain on the [production workstation roadmap](production-workstation.md).

## Continue into production

The music workflow now includes [reusable patterns and playlist placements](music-patterns.md), [song automation](music-automation.md), [channel/group/master inserts](music-mixer.md), [microphone recording and audio takes](music-recording.md), and [picture monitoring, score starts and cues](music-picture-scoring.md). These guides describe the current source versions and exact workflow bounds. The [feature sprint checklist](feature-sprints.md) separates implementation from final integrated acceptance.
