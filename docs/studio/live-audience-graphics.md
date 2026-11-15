# Feature an audience comment in the live program

Open **Live Studio → Audience desk**. Incoming messages stay in their feed until you choose **Show on program** beside one. The selected viewer name, source/platform and comment excerpt appear as a graphic in the existing program canvas, above the library overlay and clear of the bottom ticker. The same captured video supplies the private recorder and chosen broadcast destinations.

Supported selectable feeds are authorized Lightek community replies, messages from the connected session room, direct TikTok reader **chat** events and Social Stream Ninja **chat** events. Viewer counts, arrivals, gifts and other activity do not get a feature button. The Restream iframe remains an independent reading/replying view; Lightek does not extract its messages into these controls. Existing audience permissions and reader connection requirements remain in force.

## Operator workflow

1. Connect the relevant reader or session source. Lightek community replies become available through the existing audience snapshot after a Lightek/simulcast session starts.
2. Review a message, then choose **Show on program**. This selects a snapshot; later feed refreshes do not edit the selected quote. Selecting another comment replaces it.
3. Review the program preview. A ready camera/screen, library visual, room or 3D-stage source is needed to draw the graphic. Selecting a comment does not open devices, start a broadcast, write a social reply or change the destination.
4. Choose **Clear audience comment** to remove it. Entering holding screen, ending/failing the session or releasing capture also clears the selection. A message explicitly selected while holding is queued locally for the resumed program; it does not draw over holding screen.

The featured-comment panel shows the selected excerpt as plain text. All selected broadcast destinations receive the graphic when it is in the program. Reader connection status is independent from video encoding/delivery status.

## Rendering and state

The graphic uses the show's current accent color, with a bounded contrast background and plain canvas text. Names are limited to 80 Unicode code points, SSN platform labels to 24, and message excerpts to 320. The body fits at most three measured lines, with an ellipsis for overflow. Wrapping is cached per selection to keep the 24 fps paint loop lightweight. HTML tags remain text; the feature does not load avatars, images or message links.

The selection is local and ephemeral. It is not saved in a show template, production preset or room presentation, and reloads start with no selected comment. Existing original comments remain in their own source systems. No migration, new provider API or new dependency is required. Changing the active Lightek broadcast clears its feed while the new authorized snapshot loads; an older in-flight response cannot replace the new feed.

## Verification

Focused DOM/canvas-command checks cover explicit selection from community/room/social feeds, activity exclusion, text handling, bounds, clearing and stale snapshot responses. Existing server checks cover authorized audience snapshots and rendering of the live workspace. The CI browser capture fixture also checks the graphic in actual program-canvas pixels and clearing across holding/session end; workflow checks exercise the social feed's feature/clear buttons. Chromium cannot launch in the implementation container, so those browser results are not claimed as locally passed. Real reader events, device capture and final platform delivery remain integrated acceptance.
