# Live Broadcast Producer

## Prepare a show

Open **Live Studio → Prepare a show with Nevaeh**. Give the producer a title, talking points in the order you want to cover them, a destination, a house look, and an optional saved Live Studio scene. Choose **Assign show to Nevaeh**. The producer creates an opening cue, talking cards and a close, and verifies access to the scene and its prepared assets. The completed show appears under the preparation form and in the goal receipt.

## Set the look

The producer sets the broadcast frame, brand and show title, with an optional subtitle. Choose a house look such as Studio Signature, News Desk, or Lightek Originals. The frame is applied to the local program preview when you open the package. The saved scene can also supply a 3D set, saved camera framing, graphics, media and audio. Live Studio's Graphics tools remain available for adjustments.

## Host the show

Open the prepared show to see the teleprompter. Adjust **Text size** and **Scroll speed**, then choose **Play scroll**. Scrolling stops at the end of each cue. Use **Previous cue** and **Next cue** to change cards, or scroll the current card manually. **Freestyle** hides the script and pauses scrolling. When you return, the same cue and reading position are visible and you can resume scrolling.

The teleprompter stays in the host interface, outside the program compositor. For a screen-share segment, select the window or tab you want viewers to see and keep Live Studio out of the shared surface.

If there is a prepared scene, load it into the program preview. The package pins the scene revision. Prepare the show again if the scene changes. If the requested destination becomes unavailable, the interface selects a private test and displays the reason. Enable the camera and microphone in your browser, check the program preview, and use the existing broadcast controls to start and stop. Restream and TikTok confirmations use the existing flow.

## Assign it from Nevaeh

In Nevaeh, use `/live prepare SITE_ID {"title":"Lightek Live","brief":"What we shipped\nLive demo\nQuestions","destination":"test"}`. Use `house_look` such as `studio`, `news` or `cinema` and add `scene_id` to use a saved scene. The producer prepares the package through Dispatch, with this guide attached to the worker run.

The current binding prepares the rundown and workspace. Browser permission, live switching, guest connections, going on air and stopping are operated from Live Studio. The [live operations contract](../../studio/live-nevaeh-contract.md) tracks the additional producer controls.
