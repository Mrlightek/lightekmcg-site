# Agency reseller packages

The platform publishes its provider-backed servers under **Hosting packages & margins**. Agencies open **Reseller packages** to see those published packages automatically, including Lightek's marked-up wholesale price. Provider credentials and raw provider costs are excluded from this catalog.

An agency selects a source package, names its offer, sets a retail price and chooses installed feature allowances. The minimum selling price covers Lightek's entire wholesale charge plus the payment reserve. For example, a server costing Lightek $6 can have a $15 wholesale charge and a $25 agency retail price. The agency's proceeds are the remaining amount after that $15, processor/platform fees and any agreed revenue share. The checkout snapshot protects the agreed wholesale charge for that purchase and its renewals. Raising Lightek's price requires agencies to reprice insufficient offers before accepting new purchases.

## Feature profiles

Each package includes switches for websites, design, Studio, live broadcasts, rooms, reservations, commerce, shipping, marketing, mail, accounting, people, compliance, directory, communities, messaging, Susu, PWA, OTT, knowledge, payments, Nevaeh and agency/reseller tools. Agencies can reduce their source package's allowances; they cannot enable an upstream-disabled feature or remove an upstream ceiling.

Each feature optionally limits successful write requests per UTC calendar month. These are HTTP write requests, not business units such as messages sent or render minutes. Reads do not consume the allowance. Failed requests release their reservation. Blank means unlimited when the source package allows unlimited. Zero writes permits viewing while preventing writes.

Instance limits cover websites, user accounts and media storage bytes. The initial website and owner count toward the first two. Media limits cover uploaded blobs before direct-upload credentials are issued and count a shared attachment once. CPU, RAM and disk are determined by the provider server plan. An unlimited application allowance does not add physical server capacity.

The policy restricts existing role permissions; enabling a feature does not grant another user's data or an administrative role. Disabled features are filtered from navigation and rejected by controller, PWA policy and mapped capability checks. Normal client administrators remain subject to their package. Platform super administrators retain an override. Authentication, MFA, password recovery, personal settings, support and authenticated platform callbacks remain available.

## Checkout and installation

The existing central reseller federation supports catalogs and offers on an agency's separate installation. Checkout freezes the selected feature profile and wholesale charge. Both native Rails and container provisioning pass the profile to the target installation. Provisioning verifies authenticated source and policy-digest evidence before marking delivery complete. Container images must contain this implementation; old images fail closed when asked to install a managed package.

Editing an offer affects subsequent purchases. Existing installed policy snapshots and subscription wholesale terms are not silently rewritten. This release does not provide a live push editor for existing client limits, OS hosting-account management, or automatic migration of existing client installations. The existing demos workflow still needs its own configured upgrade product; publishing a remote reseller offer does not mirror it into that installation's local demo-upgrade product list.

## Validation

Run `ruby test/standalone/agency_reseller_checks.rb`, `ruby test/standalone/agency_package_access_checks.rb`, `ruby test/standalone/reservation_federation_checks.rb` and `python3 -m unittest test/scripts/test_paid_instance_verification.py` with the public isolated dependencies from `.github/workflows/agency-reseller-acceptance.yml`. These exercise real models, controllers, database transactions and installation evidence, with provider/payment calls stubbed at external boundaries. A paid production install remains a separate acceptance checkpoint.
