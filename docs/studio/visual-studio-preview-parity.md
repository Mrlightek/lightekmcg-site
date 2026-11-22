# Visual Studio 3D preview and export

Visual Studio resolves the original upload or the prepared starter's native file for both pose previews and MP4 export. A Blender file with multiple scenes uses the first scene by name and its first render-enabled view layer. A glTF file uses its declared default scene, or its first scene when no default is declared. Studio retains dependencies such as armatures and constraints. Collection render flags, view-layer exclusions, and object render flags determine whether geometry appears. Viewport-only hide flags do not remove geometry. Studio excludes imported cameras and lights, plus starter objects named Studio floor or marked with `lightek_character_floor`.

For a native model, select the action and frame, then choose **Build pose preview** in the Inspector. The worker evaluates geometry in Blender at that frame. With no frame specified, it samples frame 1. The resulting GLB is a static pose with no animation clips. An MP4 with an explicit pose frame uses the same evaluated geometry. When no pose frame is set, the MP4 evaluates the native animation over time. Direct glTF assets expose the clips loaded by Three.js and use the one-based Studio frame clock for pose selection.

Preview cache entries are scoped to the asset and keyed by source blob revision, action, pose frame, and FPS. The generated GLB stores Y-up coordinates. A dedicated Three.js parent converts them to the Studio Z-up stage, preserving the imported scene's local transforms and animation tracks.

## Lighting and reference check

The viewport uses a hemisphere fill, a directional key positioned at `[0, -4, 4]`, and a neutral background. The MP4 uses Blender Cycles with a neutral world, a disk area key at `[0, -4, 4]` tilted 55 degrees, and Blender's Standard view transform. Both use Studio lighting. The light models, color handling, materials, and shadows can differ, so use a Blender frame as the reference for final appearance.

Run the Blender reference check to compare visibility and evaluated world-space vertices in the MP4 scene assembly and the generated GLB.

```sh
blender -b -t 2 --factory-startup --python-exit-code 1 --python test/standalone/studio_animation_preview_reference.py
```
