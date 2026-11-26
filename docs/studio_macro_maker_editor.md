# Studio Macro Maker editor

The editor opens at `/studio/macro_maker` on the tenant's Studio host. The list shows the latest published version and the caller's own drafts for the chosen surface. Each link reopens that specific version. Saves use the same site-scoped composition store and chain validation as the v1 JSON API.

The ordered cards use Rails-rendered field templates with Stimulus-held state. Add, edit, cancel, remove, capture, bind, and reorder work locally. Saving or publishing submits the full definition through Turbo. A successful save updates the header, chain, and validation frames. A 422 updates only the validation frame, so the in-memory chain stays available for correction.

The image catalog includes **Set Layer Opacity** for binding a previously captured layer. Capture `hair_layer` from **Add Facial Hair**, then select it for the opacity operation's **Layer** input. Compatible handle types appear in the same picker with their type labels.

The helper renders point, polygon JSON, color, layer handles, generic JSON, and standard numeric and text fields. All controls exposed by the built-in catalog are covered. Generic objects, unspecialized arrays and unknown Studio types raise instead of falling back to strings. Multiple accepted handle types share one picker and a single literal editor anchored to the declared schema. The editor does not generate different literal editors for each accepted handle type.

## Browser acceptance

The standalone browser fixture uses Rails, Turbo, Stimulus and a temporary PostgreSQL schema. Set `PHOTOCRAFT_CLI`, `EFFECTCRAFT_CLI` and `STUDIO_RECIPE_TEST_DATABASE_URL` as for the API checks. With Playwright and Chromium available, start the fixture and run the browser driver in a second process.

```sh
BUNDLE_GEMFILE=test/standalone/macro_maker_browser.Gemfile bundle exec ruby test/standalone/studio_macro_maker_browser_server.rb
node test/browser/studio_macro_maker.mjs
```
