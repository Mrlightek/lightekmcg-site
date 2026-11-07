# HTML/CSS website imports and shop designs

Website tools → Website designs → choose a website → Upload & convert design.
Upload a UTF-8 HTML file and optional CSS file (500 KB each). The conversion saves the original source in the import record, creates an owned Design
Studio workspace, releases a version to the website design library, and optionally
creates an unpublished Page with ordered Sections. The upload request completes conversion immediately so no separate worker is
needed. Open the workspace, preview, or Pages & Sections. Existing page publishing and
home page selection remain under the website editor's control.

Each top-level body element and each direct child of main becomes an editable
section. Text, link destinations and image URLs have ordinary collection fields;
HTML/CSS remain available for advanced editing. Sections can be reordered,
duplicated, removed, copied into designs, and released using the existing Studio
versioning flow. Source layout CSS lives in isolated shadow roots, with local
html/body/:root selectors, media queries, keyframes and Google Fonts retained.
Header/footer imports suppress duplicate website chrome when the design is used.

The importer converts static HTML and CSS. It does not execute uploaded
JavaScript, submit uploaded forms, fetch external stylesheets, or resolve local
asset bundles. Host images first and upload external CSS as a file. Import notes
identify these limits. Review previews before publication. Script-driven visibility
using the supplied designs' `.rv` class is reset so content is visible.

For a shop layout, enter the product container selector. For the supplied
`LightekMCG Store.html`, enter `#grid`. The matching top-level section becomes
`lightek_product_grid`, using only the selected website's published products,
photos, prices, variants and Add to cart actions. The uploaded JavaScript catalog
is not converted into inventory. Product management and checkout remain the
existing Commerce system. Publishing the generated page enables its styled
`/commerce/shop?site_id=...` route; a draft does not replace a published shop.

Industry starters now produce six-section templates: illustrated hero,
collection cards, live products, brand story, cart CTA and footer. Retail, Beauty,
Food, Creators and Services have distinct palettes, copy and local SVG artwork.
They create a reusable library design plus an independent editable draft for the
chosen website. Reusing a starter returns that same page without overwriting
edits. Templates create no fake stock, products, reviews or performance claims.

No migration or new worker service is required. Deploy the source and restart
Passenger and the existing Sidekiq worker. Interactive HTML imports run immediately
through the same idempotent job. Optional background submissions still use the
default queue. Existing queued or failed uploads have a Convert now / Retry
conversion action that reuses their saved source without uploading again.

## Verification

`ruby test/standalone/html_design_checks.rb` exercises the actual conversion and
normalization services against both supplied HTML fixtures, copy/link/image edits,
CSS isolation and sanitization, malformed and oversized uploads, and all five
industry layouts. Rails integration/service tests cover authorization, job
idempotency, original source retention, publication, site isolation and recovery.
Run those in the application's normal Ruby/Bundler/PostgreSQL environment.

Local verification: 7 conversion tests / 103 assertions and 7 persisted job tests /
35 assertions passed using Ruby 3.2 and a minimal Active Record 6.1 SQLite harness.
All 16 changed ERB templates compiled; Ruby/JavaScript syntax and diff checks passed.
The app's full Rails 8/PostgreSQL tests and browser visual checks are not verified
in this workspace. Browser installation was unavailable. The persisted harness
uses stand-in CMS models and does not replace full host acceptance.
