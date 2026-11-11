# Visual Studio

Dashboard → Studio → Open studio opens one scene around a live 3D stage.

1. Create a scene with a project name, or open an existing scene. Production templates are under **Start from a production template** on the Studio home screen. They create scene structure and camera coverage; add your own cast and recordings.
Use **Save show template** to copy the current project into a reusable show setup. On the home screen, open production templates and choose **Create episode** on a saved setup to make an independent copy.

2. Add a saved character from **Characters**, or choose **Create toon character**. A toon build runs in the background. Its processing or failure status appears in the sidebar; add it when ready.
3. Select an item on the stage or in **In this scene**. Use **Move**, **Rotate**, or **Scale** in the stage toolbar. Drag to orbit, right-drag to pan, scroll to zoom, and **Frame** to find the selected object.
4. For a character, choose or upload a recording on the right. **Save & watch take** saves the performance and renders up to three seconds inside the stage. Mouth automation follows volume; it is not phoneme lip sync. Take timing is available in a disclosure.
5. **Sets & props** adds procedural floors, rooms, rooftops, or imported models. **Media** uploads and adds prepared video, audio, or images to the media edit. Clips appear in the timeline; drag one to move it or select it to adjust trim, volume, and track. Changes save through the existing timeline API.
6. **Play edit** previews the media timeline. **Layout** returns to the interactive scene. **Camera preview** renders a low-resolution still from the saved camera. These are separate views of the production: the browser layout does not perform final Blender rendering.
7. **Export** requests an existing render quote for the current scene, or a timeline quote when Media edit is active. The existing quote, checkout, operation history, and publishing controls remain in Advanced tools. **Back to visual studio** returns to the stage.

A rendered shot still needs to be added to a media assembly through Advanced tools → completed export → reuse in editing library. The visual view does not automatically combine a live 3D stage with the video edit. Detailed rig bindings, freeform authoring, camera settings, face cues, finishing, and publication remain in Advanced tools. This is a simpler entry into the existing engine, not a claim of Blender/Maya parity.

## Validation

`test/javascript/studio_visual_test.cjs` exercises selection without viewport replacement, recording saves and previews, media addition, clip edits, template access, and returning from Advanced tools. Existing performance and finishing UI tests cover the retained controls. The standalone performance suite exercises real Blender generation and audio/video rendering when `LIGHTEK_TEST_BLENDER=1`.

Browser screenshot verification could not be completed in the Work environment: its cloud browser cannot reach the local HTTP server and blocks file URLs. Review the deployed interface at desktop and mobile widths before calling visual acceptance complete.
