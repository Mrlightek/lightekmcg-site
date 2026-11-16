# Dashboard usability review and first changes

Reviewed the shared sidebar, dashboard home, client home, business hub, agency account screen and navigation defaults on 2026-11-16. This is a source review; it is not a completed production usability study.

## Findings

- The sidebar put business, content, team and infrastructure destinations in one long Workspaces group. Default navigation now uses expandable task categories. The current destination's category opens automatically; other tools remain available through category disclosure or Find a tool.
- Home repeated six business links for each website, in addition to a separate business banner. Home now starts with task cards and one workspace link per website. Studio and agency cards follow their existing role/feature conditions.
- The business hub displayed roughly 17 links before its metrics. Four common tasks now lead: sell a product, manage orders, update the website and set up payouts. The other destinations are in More business tools. Links retain the selected website ID.
- System diagnostics occupied the home page alongside customer work. They now sit in System health & automation; the summary still shows the number of open support tickets requiring attention.
- The agency screen began with enabling a reseller and editing branding, before client operations. It now opens one authorized agency at a time, leads with client creation and email search, and returns new clients to a setup panel. Branding, revenue terms and agency promotion are disclosed when needed.

## Behavior

Default category and label changes do not rewrite saved sidebar preferences. Custom labels, grouping and hidden destinations remain honored. Existing role, feature and reseller package filtering still runs before rendering. Search only filters the rendered destinations locally; it does not add permissions or query another account's data.

Tool search opens matching groups, shows an empty result message and restores disclosure states when cleared or dismissed with Escape. Turbo cache cleanup clears the filter and removes its listeners. Categories remain accessible as native disclosure controls without JavaScript. The old collapse-state script was removed so stale browser preferences cannot close the current page's category.

## Validation and remaining work

`test/standalone/dashboard_task_navigation_test.rb` checks operator, agency and client destination visibility against the helper. `test/javascript/dashboard_navigation_browser_test.cjs` exercises the navigation fixtures with the production CSS/JavaScript in Chromium and WebKit, at desktop and mobile sizes, in light and dark palettes. It covers no-JavaScript disclosure, search, empty results, keyboard access and Turbo restoration. These checks are included in Dashboard appearance CI.

The new cards link to existing workflows. This change does not claim to implement a guided product-to-checkout or client-to-launch wizard. Next, review the actual agency and merchant journeys in a signed-in session and observe a first-time user completing a task without verbal guidance. Check next-step clarity, preserved account/site context, completion feedback and recovery when setup is incomplete.

## Agency client setup follow-up

The selected agency is resolved through the existing `agency_scope`; the selected client must be a direct client account of that agency. Client selection is independent of the email search, so filtering the list cannot change the client whose setup is displayed. Search is case-insensitive, escapes SQL wildcards and returns at most 100 accounts.

Client creation and invitation resend return to the same agency/client setup anchor. A pending password is described as pending; the interface does not claim that mail has arrived or that MFA enrollment is complete.

Choose a hosting plan carries `hosting_owner_id` to the existing catalog. The hosting controller resolves that value against the actor's permitted account list, and each package form preselects it. The operator may select any account, as already allowed by the purchase authorization service. No purchase, payment or provisioning occurs on these GET requests. The existing checkout POST rechecks management permissions and still requires confirmed payment before installation.

The setup panel shows at most ten installation receipts visible through the existing installation scope, filtered to the selected owner. It links to their existing installation detail pages. Website links are the intersection of the actor's authorized websites and the selected client's available websites. A ready remote installation does not imply it is editable from this central instance; its installation page remains the access handoff.

A recorded installation is shown before offering another purchase, to reduce accidental duplicate subscriptions. Hosted services are not marked ready merely because the account was created. If the client purchased an installation that the agency cannot see through the existing receipt scope, the workspace does not broaden receipt access.

`test/standalone/agency_workspace_checks.rb` exercises the real agency and hosting views with a database account graph: client creation handoff, owner preselection, escaped email search, website/receipt filtering and rejection of foreign agency/client/hosting selections. Existing onboarding checks retain their real invitation assertions and now expect the selected setup redirect. Browser and signed-in production walkthroughs remain separate acceptance work.
