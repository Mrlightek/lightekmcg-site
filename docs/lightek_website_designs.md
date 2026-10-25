# Website designs and visual fonts

Open Settings → Website designs & fonts. Choose the website explicitly when more than one is available.

- **Preview design** displays the complete client layout without creating records.
- **Apply design** selects a presentation template owned by that website. It leaves pages, sections, navigation records and publication states intact.
- **Import starter page** creates an unpublished page containing seven VinylCTRL sections or nine YBNC sections. It does not replace the homepage, apply the design or publish anything. A repeat import returns the same page, preserving changes to its title, slug, section content and publication status. If the page was deleted, importing creates a new draft.
- **Typography** saves the body, heading and monospace choices to that website's design copy. Switching away and back retains that copy. The visual browser searches a bundled catalog of 1,950 Google font families and loads previews twelve at a time. Fonts themselves are requested from Google, as in the existing font loader.
- **Pages & Sections** uses the existing editor to change the imported copy, link destinations and section order. Fields preserve the source layout's inline emphasis and structure. The original client applications' data, users, business logic and credentials are not imported.

Existing CMS navigation remains in use when a website has a menu. The starter designs' navigation is the fallback for previews and sites without a menu. Starter footers are included in editable content. On other pages, an existing CMS footer is retained; otherwise the design's starter footer is shown.

Signup demonstrations are disabled and clearly marked as unconnected. The imported sample DJ profiles, quotes, impact figures and event details are starter content. Review and replace them before publishing. Booking, newsletter, donation and other service integrations remain separate from applying a visual design.

The original site's publication and hostname lookups run before custom public rendering. Design controller actions scope websites through the existing WebsiteIdentity service. Super admins can select all websites; admins can select their own. Pages, Sections and Templates editors share that selection rather than defaulting to the first website. Design template metadata survives updates through the legacy template form.

## Installation

From your lightekmcg-site checkout:

```bash
bash ~/Downloads/lightek_website_designs_install.sh
APPLY=1 bash ~/Downloads/lightek_website_designs_install.sh
```

The first command checks the proposed changes. The second backs up changed files, installs the source, runs Zeitwerk and the design/font tests, and prints the backup directory. It does not migrate a database, change production records, deploy, commit or push. Restart Rails after a successful installation.

To undo an installation before making further edits to its files, run the generated backup's `restore.py` using Python 3. It refuses to overwrite files changed since installation.

## Verification

The recovered-source harness uses Active Record 8.0.4, SQLite and the supplied DymondSite models: six service tests, 58 assertions, no failures. Both complete layouts were rendered with Action View 8.0.4. JavaScript and Ruby syntax were checked. Both layouts were checked in Chromium at 1440, 390 and 320 pixels; mobile navigation opened and closed with Escape, and no JavaScript errors were reported. The font-browser interaction check exercised its 1,950-family catalog, twelve-card pagination, handwriting filter, selection and Escape handling. Installer checks verified dry-run/conflict behavior, backups and exact restoration after a simulated unavailable host check. The installer additionally runs the HTTP integration tests and autoload checks against the actual host application; those full-host results cannot be established from the source excerpts alone.
