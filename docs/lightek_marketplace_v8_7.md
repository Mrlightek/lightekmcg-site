# Lightek Marketplace V8.7

Public discovery: /marketplace. Administration: /dashboard/marketplace.
Catalog owns merchandising in DymondCatalog::MarketplaceListing. Each row references a canonical DymondBank::Offer. No prices are copied. Only published listings with active offers appear publicly. Super admins can create, edit, publish and unpublish through Dashboard. The installer creates hosting candidates as drafts from Bank offers whose subscription plans have infrastructure entitlements; inspect the candidate before publishing.

Detail pages obtain due today, recurring amounts, setup fees, trial days, and terms from DymondBank::Checkout.preview. Continue to checkout uses the mounted Bank checkout route, retaining its authentication and customer identity boundary. This release does not modify Bank checkout, Stripe, ledger, settlement, or Gatekeeper execution. Settlement-to-provisioning remains subject to separate end-to-end verification; a Marketplace page is not proof of fulfillment.

The store uses scoped CSS with --lightek-* token fallbacks and the app stylesheet bundle. The written design direction was recovered; this is its implementation, not a verified pixel-for-pixel recreation of the missing visual previews.

The engine's current Dashboard layout is copied into a host override only when needed; a super-admin commerce navigation partial is inserted immediately before its content yield. Existing layout contents are preserved. HTML /catalogs redirects to /marketplace; existing JSON and member CRUD routes are preserved.

Install from the Rails host root with bash lightek_v8_7_marketplace.sh. It validates contracts, checks source collisions, backs up changed files and db/schema.rb, installs, migrates development and test, creates draft merchandising, and runs autoload and focused acceptance checks. Rerunning is idempotent. Set CHECK_ONLY=1 for contract inspection without source writes. It does not commit, push or deploy. Production mode is refused to avoid migrating a live host through a local development installer.

Backups and an installation manifest are stored under tmp/lightek_marketplace_v8_7/. A failed verification leaves files available for diagnosis and prints the backup location; it does not silently claim success or roll back database migrations. To undo, use the manifest to restore prior files and remove files marked as newly created. If no other migrations followed, the dedicated migration can be rolled down after reviewing and exporting any listings. Original Catalog, offers, plans, subscriptions and purchases are never deleted.

Tests shipped: public page and filters, legacy HTML route and JSON preservation, hidden/nonexistent listing response, signed-out admin denial, route precedence, inactive-offer publishing, invalid category/position. Additional authenticated write and customer purchase/fulfillment checks should run on the installed application before public launch.
