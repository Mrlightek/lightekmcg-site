# Dashboard usability review and first changes

Reviewed the shared sidebar, dashboard home, client home, business hub, agency account screen and navigation defaults on 2026-11-16. This is a source review; it is not a completed production usability study.

## Findings

- The sidebar put business, content, team and infrastructure destinations in one long Workspaces group. Default navigation now uses expandable task categories. The current destination's category opens automatically; other tools remain available through category disclosure or Find a tool.
- Home repeated six business links for each website, in addition to a separate business banner. Home now starts with task cards and one workspace link per website. Studio and agency cards follow their existing role/feature conditions.
- The business hub displayed roughly 17 links before its metrics. Four common tasks now lead: sell a product, manage orders, update the website and set up payouts. The other destinations are in More business tools. Links retain the selected website ID.
- System diagnostics occupied the home page alongside customer work. They now sit in System health & automation; the summary still shows the number of open support tickets requiring attention.
- The agency screen begins with enabling a reseller and editing branding, before client operations. This remains a follow-up workflow change: lead with client creation, package assignment and launch progress.

## Behavior

Default category and label changes do not rewrite saved sidebar preferences. Custom labels, grouping and hidden destinations remain honored. Existing role, feature and reseller package filtering still runs before rendering. Search only filters the rendered destinations locally; it does not add permissions or query another account's data.

Tool search opens matching groups, shows an empty result message and restores disclosure states when cleared or dismissed with Escape. Turbo cache cleanup clears the filter and removes its listeners. Categories remain accessible as native disclosure controls without JavaScript. The old collapse-state script was removed so stale browser preferences cannot close the current page's category.

## Validation and remaining work

`test/standalone/dashboard_task_navigation_test.rb` checks operator, agency and client destination visibility against the helper. `test/javascript/dashboard_navigation_browser_test.cjs` exercises the navigation fixtures with the production CSS/JavaScript in Chromium and WebKit, at desktop and mobile sizes, in light and dark palettes. It covers no-JavaScript disclosure, search, empty results, keyboard access and Turbo restoration. These checks are included in Dashboard appearance CI.

The new cards link to existing workflows. This change does not claim to implement a guided product-to-checkout or client-to-launch wizard. Next, review the actual agency and merchant journeys in a signed-in session and observe a first-time user completing a task without verbal guidance. Check next-step clarity, preserved account/site context, completion feedback and recovery when setup is incomplete.
