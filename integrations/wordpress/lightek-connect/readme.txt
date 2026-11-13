=== Lightek Connect ===
Contributors: mrlightek
Tags: agency, hosting, dashboard
Requires at least: 6.5
Tested up to: 6.5
Requires PHP: 8.0
Stable tag: 0.1.0
License: GPLv2 or later
License URI: https://www.gnu.org/licenses/gpl-2.0.html

Connect your Lightek agency account to manage client environments.

== Description ==
Creates a Lightek admin workspace. Each WordPress administrator connects their own Lightek account. Connection credentials are encrypted with the site's authentication salt and are never sent to browser JavaScript. Changing the salt requires reconnection.

== External services ==
This plugin connects to https://lightekmcg.com only after an administrator explicitly enters a connection code. It sends that code, authenticated requests, requested client identifiers and website edits to Lightek. It retrieves agency/client information, website names and deployment statuses. Full Dashboard access uses a short-lived management link. No WordPress posts, WooCommerce orders or customer records are synchronized. Lightek service terms and privacy policy must be published and linked here before directory submission.

== Installation ==
Upload the lightek-connect folder, activate, open Lightek in the admin menu, and enter a WordPress connection code from Lightek Dashboard → Lightek Connect.

== Frequently Asked Questions ==
= Does uninstalling revoke access? =
Disconnect before uninstalling, or revoke the connection from Lightek Dashboard. Uninstall deletes local credentials.
= Can other administrators use my connection? =
No. Credentials are stored per WordPress user.

== Changelog ==
= 0.1.0 =
Initial development release. Directory approval and production acceptance are pending.
