# Website template library

Open Dashboard → Design & Content → Website designs. The library includes the existing Lightek originals and twelve industry starters: restaurant, barber, fitness, real estate, law, community, medical, home services, photography, boutique, music and hospitality. The supplied Free/Pro guesses are not treated as subscription entitlements; these are included defaults. Custom released designs remain scoped to their existing owners.

1. Choose the website you manage.
2. Search or filter the library. Preview opens an isolated, nonpublishing preview.
3. **Use template** applies its appearance and creates an editable draft in Pages & Sections. Existing pages remain. Reusing the same template returns its existing draft/page and preserves edits.
4. Replace fictional names, reviews, prices, dates and contact details before publishing. Replace gradient/initial image slots through the section's Image URLs collection.
5. Use Design Studio's **Customize in Studio** cards to create your own independent reusable workspace. Typography and the four main palette tokens affect the starter renderer. Publish a workspace version through the existing release workflow; applying a released design remains a separate action.

## Content and section schema

The supplied manifests are installed in `config/lightek_designs/starters/manifests/`. The authenticated library provides their JSON download. Original source HTML is installed alongside them; it is never executed as a full document or as arbitrary uploaded code.

`LightekDesign::StarterLibrary` maps each `data-section` node to a registered Dymond Site section with a stable `starter_<template>_<section>` kind. The existing Studio document adapter uses the `starter` block and fields `template_key`, `section_key`, `copy`, `links`, and `images`. This preserves the supplied cards/tabs/stats/quotes/people/pricing/steps/FAQ/CTA/contact/listings/rooms/products/gallery/tracks/badges/calculator/donate structure without inventing unsupported Dymond Site schemas. Section markers, icon markers and image slots stay in the rendered markup.

Text is escaped and links/images are URL-validated. Scripts are excluded; maintained runtime code supplies mobile navigation, tabs with keyboard navigation, pricing toggles, slot selection, the mortgage estimator and gallery lightboxes. Source styles load inside Shadow DOM with a fallback for browsers without declarative Shadow DOM. The public palette and font settings override the original theme tokens.

## Requests and commerce

Published starter forms POST to `/website/template-inquiries`. The server resolves the website from its hostname, requires that the corresponding starter form belongs to a published page, verifies CSRF, rate-limits submissions, validates fields, and stores the request. The latest 50 requests appear below the selected website's template library. Submission errors retain the form and do not display a success message.

These are inquiries, including appointment, room, donation and product-interest requests. They do not reserve inventory, book appointments, send email notifications or take payment. The separate **Shop templates with live checkout** group uses the existing website products and checkout. The boutique starter's demo cart buttons instead lead to product inquiries. Artist track controls stay disabled until a real audio integration is supplied. Keep the medical form's warning against entering sensitive medical details.

## Attribution and white-label agencies

Regular Lightek websites display **Template by LightekMCG**. Editing the footer copy or requesting hidden credit cannot override that policy. A super admin can enable white-label customization for an individual website; a tenant's active `white_label_agency` entitlement also qualifies. An authorized agency can then change/hide its credit for websites it manages. Ordinary admin status alone does not grant the entitlement, and agencies cannot grant it to themselves through the branding endpoint. Super admins can revoke an individual website grant; an independent account entitlement still applies until revoked.

## Deployment and extensions

Run migration `20261108170000_create_website_template_inquiries`. The default catalog reads installed files and requires no seed job, external artifact links or background conversion. Source pack updates are deployed with the application.

The native request inbox is paginated by a latest-50 window; older records remain in the database. Integrate notifications/booking/payment workflows separately through normal verified capabilities. Add future templates by installing source HTML, a corresponding manifest, scoped CSS and a preview image, then running `test/standalone/starter_library_http_checks.rb` and browser acceptance. Keep the template schema fixed or version the adapter when changing structure.
