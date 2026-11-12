# Design & Content: one website, shared business tools

## Everyday work

Open **Dashboard → Design & Content** and choose the website. **Open Pages & Sections** is the first action, followed by Design Studio, articles and the store. The large page-design library starts collapsed. The selected website is retained in the Dashboard session and in action links.

## Make a complete website theme

Under **Site themes**, choose either:

- **Build a website theme from your design library.** Name the theme, choose its home design and up to seven additional page designs, then optionally include a native store and journal. Already imported pages retain their edits and publication settings. New store/journal pages use live application sections instead of demo products/posts.
- **Install a website theme from HTML.** Choose up to ten matching HTML pages and optional shared CSS. Select the home page from the uploaded filenames. `index.html`/`home.html` is detected by default, otherwise the first file is used. Files named store/shop and blog/journal are mapped to the native applications. Store HTML needs `[data-lightek-products]`, `#grid`, or the supplied product selector; blog HTML needs one `main` area.

Installation does not activate the theme or publish new pages. Review Pages & Sections, publish the pages that should be public, then choose **Activate website theme**. Activation retains existing menu entries and adds the bundle's pages without duplicates. It applies the common palette/fonts and shared imported header/footer; the header's navigation comes from the site's existing navigation records. Editing the source home page's header/footer section data updates the shared chrome across themed pages, articles and the storefront.

Ordinary CMS page URLs use `/site/:slug`, while the root/home behavior remains with the site's existing home page. Installation never replaces an existing home page's body or silently renames it. If the desired home slug already exists, uploaded pages receive a unique suffix for review in Pages & Sections. Store and journal use stable application URLs regardless of the imported page's slug.

Each installed bundle is a separate site template; preparing a second bundle does not modify the active one. Font edits retain the active bundle. The editable pages, site templates, navigation and commerce records remain the existing Dymond Site/Dymond Bank/Gatekeeper objects.

## Imported navigation and application controls

A themed imported header renders the site's real navigation, including nested links; unpublished page links stay out of that menu. Imported links can use `data-lightek-route` or the supplied examples' `data-l` values: `site`, `home`, `store`, `shop`, `cart`, `blog`, `journal`, `members`. Links to other installed HTML filenames are mapped to the published CMS page. A blog link with `data-h="#article-slug"` points to the corresponding native article route.

Store/cart links use `/commerce/shop?site_id=...` and the real cart. Members links open the site's existing PWA; they do not create a separate identity system. Uploaded prototype scripts never execute. The product container and blog area are deliberately replaced with native sections. The supplied store's script-only filter/cart overlays are removed; original uploads are retained as source in a separate owned source record referenced by the theme. Other JavaScript-generated pages with empty main content are rejected with an actionable message rather than installed as empty pages. Arbitrary forms and custom widgets still need explicit application wiring.

## Write and publish articles

Use **Write & manage articles** or **Journal & Articles** in Dashboard. Write in the visual editor, select text for formatting, set a category and excerpt, and save as Draft, Published or Archived. The URL slug is suggested from the title until manually edited. Pasted content enters as plain text. Public output permits basic article formatting and links, excluding executable HTML.

Draft previews require an authenticated website manager, use private/no-store responses and are marked noindex. Publishing creates a public article in the same `Post` record used by the PWA/community feed. Website-specific slug/category/excerpt/publication state live in `LightekBlog::Entry`, not a second copy of the article body or author. PWA cards show an excerpt and a link to the full website article. Authorized managers open the native Dashboard article editor from the PWA; generic post updates/deletions cannot bypass article revision/publication/archive controls. Archiving or reverting to draft hides that shared post and removes the article from public pages and RSS. Native PWA moderation/visibility/expiry changes also constrain public blog access.

Public routes are `/blog`, `/blog/:slug` and `/journal.xml` (RSS). Listings support search, category filtering and pagination. Hostname lookup selects the website; a query-string site ID cannot expose another website's articles. URLs are unique within a website. Optimistic locking prevents an older editor tab from overwriting a newer article or partially changing the shared post.

## Deployment and acceptance

Apply migration `20261112170000_create_lightek_blog_entries` and restart Rails/workers as usual. The PWA shell cache version changes so existing installations receive the article-card update after their normal worker update/reload.

Acceptance uses real Active Record transactions, production controllers/services/views and public-host lookup. Private Dymond engine record/registry interfaces and host authentication are isolated fixtures. Tests cover draft bundle creation, activation, shared chrome edits, existing-design assembly, font preservation, ownership, publication visibility, CSRF, conflicts, RSS and real product/cart rendering. PostgreSQL migration up/down/up verifies foreign keys, cascade deletion and per-site URL uniqueness. Browser tests exercise rendered content pages at desktop/tablet/phone sizes, visual-editor focus/formatting, slug suggestions, theme file/home selection and shared navigation. Payment is not charged and no production theme or page is activated by this PR.

This delivers website theme coordination and a managed journal alongside the existing commerce stack. It is not an import of WordPress plugins or arbitrary JavaScript applications. The uploaded careers/members/business examples guide the integrated platform direction; this change does not create new HR or membership backends or claim the complete ERP/accounting scope is finished.
