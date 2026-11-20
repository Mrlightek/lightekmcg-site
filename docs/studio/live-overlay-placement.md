# Position graphics in Live Studio

Open **Dashboard → Live Studio → Library sources · clips, graphics & sound**. Choose a prepared library image under **Graphic overlay**, then **Load selected library media**. A transparent PNG is useful for a logo, watermark or lower-third graphic. Existing permissions and proxy checks still apply.

## Place and review

1. Under **Graphic placement · 1280 × 720 program**, set **Left** and **Top** in program pixels. Set the bounding **Width** and **Height**.
2. Choose **Preserve aspect ratio** to fit the image inside that box without distortion, centered in its unused space. **Stretch to box** fills it exactly, retaining the original full-frame overlay behavior.
3. Adjust **Opacity** from 0 to 1. Uncheck **Show graphic in program** to hide it while keeping the image loaded and its placement intact.
4. Review the actual program preview. These controls update the same canvas used for local recording and broadcast. While a broadcast is active, changing a valid control changes its program immediately.
5. To reuse the placement, choose the production in **Production setup**, check its saved setup and **Save current controls to production**. Later, **Load saved setup into preview** restores the authorized graphic reference and placement along with the other source controls. Loading remains blocked during a broadcast and never starts one.

For example, place a logo near the top right using Left 920, Top 40, Width 300, Height 150, Preserve aspect ratio and Opacity 0.8. Preview it against the actual source and leave appropriate title-safe margins for the destination. A full-frame transparent lower-third can keep the default box and use its alpha channel.

**Reset full-frame graphic** restores Left/Top 0, Width 1280, Height 720, full opacity, visible and Stretch to box. It does not change the selected library image or start capture. Switching images retains the current placement until reset or setup loading.

## Layer and holding behavior

The image draws above the active camera, screen, library program, session composition or 3D stage. Selected audience-comment graphics draw after it and therefore appear above it. Only this one library image overlay is controlled here; participant-room titles/branding remain in their existing presentation controls. This does not create a multi-layer graphics editor or animated graphic cue system.

Holding screen hides the graphic; resuming restores its selected visibility and placement. Clearing library media or releasing capture removes the loaded image. The numeric controls can remain available for the next load; they do not make an unloaded graphic appear. Opacity is restored after drawing so it cannot affect later comment/title rendering.

Invalid input keeps the last valid placement in the program and shows a message. Save is rejected until values are corrected or reset, so an invalid field does not silently save a different preview state. Empty numeric fields are invalid.

## Saved contract and limits

| Field | Saved range/behavior |
| --- | --- |
| `enabled` | Boolean; hiding preserves its asset reference and controls |
| `x` | −1280 to 1280 program pixels |
| `y` | −720 to 720 program pixels |
| `width` | 1–1280 pixels |
| `height` | 1–720 pixels |
| `opacity` | 0–1; combines with the image’s own transparency |
| `fit` | `stretch` or `contain` |

Negative positions allow partial off-screen placement; the program canvas clips the image at its edges. The preview’s responsive display size does not change these program coordinates. The server rejects unknown fields, invalid booleans, unsupported fit modes and out-of-range/nonfinite numbers. Placement fields cannot contain asset URLs or credentials; the image reference remains the separately authorized `overlay_asset_id`.

New production setups use version 3, retaining version 2 show styling and existing stage/media/subject controls. Version 1/2 loading resets graphic placement to its historical full-frame defaults. A version 1/2 save cannot overwrite version 3 and discard placement. No database migration is required. Saving a show template or creating an episode copies the setup; editing the episode’s graphic controls does not change the template. Asset proxies themselves remain shared library references, as in other live setup fields.

Pending local changes must be saved to the production setup to survive navigation. Saving/loading a setup does not write room presentation state, request device permission, connect a room or purchase/start a broadcast.

## Verification

Focused Rails/HTTP checks cover version 3 round trips, scene locks, asset/site/access boundaries, malformed values, downgrade protection, template/episode independence and rendering the actual Live page controls. DOM checks cover valid/invalid edits, reset, setup save/load and legacy default restoration. A real PNG/native-canvas test checks pixel placement, aspect padding, alpha blend, off-screen clipping, hidden/zero-opacity output and canvas-state restoration.

The existing Chromium library/program test is extended with actual program-canvas position/opacity/holding pixels and version 3 source loading/saving. It is queued for CI; Chromium cannot launch in the implementation container, so that browser result is not claimed as locally passed. Real devices, multi-person sessions and destination playback remain in the integrated verification sprint.

## Create a graphic in Live Studio

Open **Program graphics**, enter a title and optional subtitle, choose a placement and accent color, then select **Show / update graphic**. Check the program preview before broadcasting. **Hide graphic** removes it from the program. Graphics are local to the current Studio session and appear in the same canvas as the library image and featured comment. The holding screen hides the graphic and ending the session clears it. A private recording can verify the combined output.

## Frame the broadcast and replace the camera background

Open **Broadcast frame & green screen**. Choose News desk or Sports desk, set the name and optional headline, and select **Apply to program**. The frame works with every program layout. It stays off the holding screen.

For a virtual backdrop, use **Camera only** with a physical green or blue screen. Select a studio backdrop or a local PNG, JPEG, or WebP image, then apply it. Set the screen color to match your setup. Lower key strength to remove weaker green or blue tones, or raise it if parts of the presenter disappear. **Animate studio backdrop** adds motion to the built-in designs. Check a private recording to see the composite before broadcasting.

To reuse a design, name it and select **Save theme** in the matching creator. Frame themes save the style, badge, text and palette. Background themes save the studio pattern, palette and motion settings. Camera key controls stay independent. Select a saved theme, choose **Load theme**, then **Apply to program**. Themes are saved per website in this browser.

## Run a holding break

Open **Holding screen & commercial breaks** and customize the site's slate. Choose up to three images or videos from the Studio library in playback order and, optionally, a separate music bed. Save settings to reuse the lineup in this browser. Select **Holding screen** to run the break or **Skip to next item** to advance it. Images play for ten seconds. Videos play to the end with their own audio. The slate returns after the lineup. **Resume program** ends the break and restores the live program. An unexpected source loss shows only the slate. Use a private recording to check the audience audio on playback.
