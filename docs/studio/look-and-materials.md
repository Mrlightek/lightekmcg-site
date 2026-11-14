# Look & materials

Open **Dashboard → Studio → Look & materials** for the selected scene. These controls save Blender parameters; the render worker applies them to the native scene and its active Composite output. They are distinct from the media edit's Color controls.

## Materials

Choose an object, Cast mesh and material slot. Principled materials expose the inputs inspected from their source: surface color, metallic, roughness, transmission, refraction index, opacity, emission color and emission strength. Older imports may expose only color/metallic/roughness; reimport their source to inspect the additional inputs. Unsupported shader graphs remain available in the advanced node tools.

Move a slider or change a color, then choose **Apply material changes**. Only inputs whose displayed value changed are saved. Texture links and shader animation on other inputs remain intact. Editing a linked/animated input explicitly replaces that input's connection or animation on the rendered material copy. Color pickers convert between display sRGB and Blender's linear color values. Unchanged slider quantization and color-picker rounding do not create overrides.

Changes apply only to the chosen material slot on the chosen object or registered Cast mesh. The character's source asset and other instances retain their source materials. **Reset this material** removes this panel's overrides for that target/slot; existing source settings and earlier authoring edits remain the baseline.

Material ranges are metallic/roughness/transmission/opacity 0–1, refraction index 1–3 and emission strength 0–20. At most 128 material overrides may be saved per character/object. No browser-supplied shader code, node graph, source filename or asset endpoint is executed.

## Scene finish

| Control | Range | Blender operation |
| --- | --- | --- |
| Exposure | −5 to +5 stops | Exposure node |
| Gamma | 0.1–3 | Gamma node |
| Saturation | 0–2 | Hue/Saturation node |
| Contrast | −100 to +100 | Bright/Contrast node |
| Blur | 0–20 pixels | Gaussian blur |
| Glow | 0–1 | Fog glow |
| Glow threshold | 0–10 | Highlight threshold |

Choose **Apply scene finish** to save. The finish is appended after the native scene's existing image connection into its active Composite output. Existing upstream nodes are retained. Reapplying replaces Studio's managed nodes rather than stacking repeated effects. **Reset scene finish** removes those nodes, restores the earlier image connection and restores whether the source compositor was enabled. Other compositor outputs and unrelated graphs are retained. These are finishing controls, not a complete multilayer compositor or a replacement for custom native node authoring.

## Save, preview and reuse

Scene finish and material drafts are independent. Switching material targets retains their drafts. Applying one group preserves edits in the others. The workspace header's **Save changes** applies all pending Look/material groups. **Reload saved settings** explicitly discards drafts and reloads the server state. Navigating between Studio workspaces keeps drafts; leaving the page with unsaved appearance work triggers the existing unload guard.

**Render saved look preview** queues a real Blender draft still using the saved scene. It does not apply unsaved sliders. Pending/running/completed/failed states come from the render operation; the image appears only when an artifact is available. A preview from an older native scene revision is marked stale. Finished shot exports use the same saved look and material values. Existing show-template and episode-copy workflows retain independent appearance settings.

Saving checks the authenticated scene/site and actor-visible source, validates editable material targets, and uses the scene lock version. Request keys make retries idempotent; changing an edit cannot reuse its old key. Changes increment the native revision and are captured in render snapshots. Cast material targets are limited to meshes in the registered source and require its pinned native blob identity to match.

The sprint's focused checks cover scopes, invalid values, stale writes, request retries, per-slot sparse edits, independent drafts/copies and real native material/compositor behavior. Blender 4.5.16 rendered before/after images with a measured pixel difference, verified shared-source isolation and unchanged texture/animation preservation, and saved an editable `.blend`. Final production acceptance remains in the integrated verification sprint.
