# Nevaeh Marketing copilot

Open **Business → Marketing copilot**, or open it from Growth. Choose your
business website. Use this workspace to turn one offer into a practical week
of campaign work, existing-lead follow-through and measured review.

## Start with one offer

Complete the shared business brief in Growth: what you sell, who needs it, their
problem, your value, brand voice and goal. Use actual scope, prices and evidence.
For Lightek, a managed business website for local service businesses is an
example of a focused offer; enter the commercial details you actually support.
The copilot does not invent prices, testimonials, customer results or research.

Choose 15, 30 or 60 minutes of human focus time per day, a placement, a local
destination page and a call to action. Click **Prepare my seven-day kit**.
Preparation saves:

- A fresh daily-plan evidence revision and up to five existing priorities.
- One social campaign draft with three editable offer/problem/benefit variations
  from the reviewed brief, using the existing shared writing engine.
- One native tracked placement link, included in each variation's CTA URL.
- Seven days of authored work blocks; the combined blocks cannot exceed the
  selected daily budget. These are suggested focus allocations, not promises
  about rendering, provider processing, sales outcomes or actual completion.
- A small queue of eligible existing leads, with two outreach drafts each.
  The queue is bounded by the follow-up focus block: one lead at 15 minutes,
  two at 30 and four at 60. No leads are scraped or invented.

## Ask Nevaeh to prepare it

```text
/marketing SITE_ID
/marketing SITE_ID {"minutes_per_day":30,"source":"linkedin","destination_path":"/contact","cta_label":"Book a conversation"}
help me market my business
prepare my marketing kit for site 12
```

Replace IDs and paths with your actual business. Without an explicit ID, the
current authorized website or the sole available website supplies context;
multiple candidates require choosing a website. Finish/cancel an active
ten-task follow-up dialogue before starting a different task. Decide/Reflect
preview the action. Operate/Converse dispatch through the existing Campaign
Producer, Gatekeeper and Dispatch. The default command uses 30 minutes, a
manual placement and `/`; it does not select a social account or publish.

Use Task builder's **Prepare a seven-day marketing kit** action to add your own
phrases or fix a website input. Existing worker permissions remain required.
This action does not add labels to the ten-task neural classifier.

## Execute the plan and build the feature showcase

Click **Execute my marketing plan** and confirm the work, or ask Nevaeh:

```text
/marketing execute SITE_ID KIT_ID
/features SITE_ID KIT_ID
execute my marketing plan
build my feature page for site 12
```

Without a kit ID, the latest kit in that authorized website supplies context.
Preparation and execution are distinct actions: creating a kit does not start
rendering or create follow-up tasks automatically.

Execution saves a durable goal with an actual CMS/page/video step and one
native Sales task step per saved lead. The Website Operator creates a native
`lightek_feature_showcase` section on an unpublished page, grouped by feature
category, with benefit descriptions and media players. The first page uses
`features`; if that slug already exists, another kit uses `features-KIT_ID`.
Existing pages are retained. Repeating execution of the same kit returns its
existing goal and showcase, including any editor-renamed page.

The feature catalog contains curated Lightek platform overviews grounded in the
installed `FEATURES.md`. Disabled package features are excluded. It is not an
automatic inventory of an arbitrary client's products: review the copy for what
that website actually offers. Adding or changing these curated cards requires
updating `FeatureCatalog` and reviewing the resulting page. Native CMS heading
and introduction fields remain editable through the website tools.

The Studio queue renders one captioned MP4 overview per included feature, up to
six, using the existing bounded local media-process runner. Each is 12 seconds,
960×540, with readable text and fades. These explain the feature; they are not
screen recordings, recorded demonstrations, avatar performances or voiceovers.
Use Studio to produce genuine recorded demonstrations when those are required;
this first showcase renderer does not capture a logged-in application session.

The goal waits for saved, readable clips and verified page data. It then resolves
the first worker's journal reference and passes its site ID as a typed prior-
output dependency to the Sales worker. Each follow-up step produces or reopens
a real Sales task, never an implicit message send. A missing file, failed render,
revoked permission, stale source or changed lead blocks progress. Inspect the
goal in Nevaeh to pause/cancel it or review the blocker. Resolve failed source
or media prerequisites before preparing a new kit/goal; do not relabel a failed
job as completed or automatically replay uncertain work.

Watch the saved videos in Marketing copilot. Confirm their claims and approve
them for the page, then publish the reviewed page in the existing CMS. The
public media endpoint requires the exact website host, a published page, current
package access, explicit video approval and the actual saved file. A draft page
or an approved video alone does not grant public playback. No public page is
published or external message sent merely by executing this goal.

## Work from the kit

Review the priorities first: incoming inquiries, paid delivery obligations and
due sales work can matter more than producing another post. Open the three
copy variations in **Content variations & approval**, edit them, and approve
the exact version. Studio and Publishing remain the media/export/scheduling
tools, with their own provider receipts. Choosing TikTok or Instagram as a
placement label does not connect an account, render a video or prove a post.
The local destination syntax is checked; confirm the page exists and gives
customers a real way to inquire or buy.

Read each existing lead's context before using an outreach draft. Only active
new leads with no follow-up date, or active leads due today or earlier, enter
the kit. **Prepare or open follow-up task** reuses an existing open task, or
creates one assigned to you through the native Sales service. It does not
send a message, mark a lead contacted or complete a task. A changed lead,
changed brief or kit older than seven days blocks this operation; prepare a
fresh kit and review the current context.

Record a completed/skipped check-in and a note after each day begins. These
append-only check-ins are your account of the work, not evidence of sending,
publication or a sale. Review tracked visits, inquiries, confirmed payments
and refunds in Growth. Missing attribution stays unknown. Use Performance
when comparing two reviewed, placed versions; do not treat copy generation
or a small visit count as proof that an ad works.

## Persistence and recovery

Kits, their brief/evidence snapshots and check-ins are retained in the database.
Campaign variations, links, tasks and actual receipts stay in their existing
stores. Preparing again with the same request key and inputs returns the same
kit; different inputs or another operator cannot reuse that key. All records
are website-scoped and current account/package access is rechecked.
Kit creation is transactional: failed copy generation or acceptance checks
roll back the kit, campaign, link and new daily-plan revision together.

The migration upgrades only untouched Campaign Producer defaults to include
`growth.marketing_kit` and `growth.marketing_execute`; deliberately restricted
or deleted roles remain so. Website and Sales workers retain their existing
scopes. Execution also requires the Nevaeh package feature; rendering requires
the website, Studio and marketing features. Follow-up tasks require Commerce.
Apply `20261116140000_add_marketing_copilot` before restarting Rails, then workers.
No campaign is approved, published, sent or scheduled by the migration or kit
preparation. This release does not add autonomous ad spending, prospect scraping,
external competitor research or a guaranteed-customer claim.

Keep the Studio queue running and its existing isolated media image available.
Production uses that image through `Studio::MediaProcess.container`; it already
contains FFmpeg, FFprobe and DejaVu Sans. Development/tests use local binaries.
Keep Active Storage's configured database and media store persistent.
The feature job does not need an external generation API, a GPU or a new
inference service. Retain failed/previous kits and media as execution history.

Run `ruby test/standalone/marketing_copilot_checks.rb` for the production-model,
service, HTTP and Nevaeh dispatch checks. The host authentication and external
provider boundaries remain fixtures; perform one real kit/review after deployment.
