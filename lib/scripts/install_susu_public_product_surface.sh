#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_public_product_${STAMP}"
mkdir -p "$BACKUP"

for f in \
  config/routes.rb \
  app/controllers/susu_public_controller.rb \
  app/views/layouts/susu_public.html.erb \
  app/views/susu_public/home.html.erb \
  app/views/susu_public/pricing.html.erb \
  app/views/susu_public/onboarding.html.erb \
  app/assets/stylesheets/susu_public.css
do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

mkdir -p app/controllers app/views/layouts app/views/susu_public app/assets/stylesheets

cat > app/controllers/susu_public_controller.rb <<'RUBY'
# frozen_string_literal: true

class SusuPublicController < ApplicationController
  allow_unauthenticated_access only: %i[home pricing onboarding]
  layout "susu_public"

  def home; end

  def pricing
    return unless defined?(DymondBank) && DymondBank.respond_to?(:configuration)

    config = DymondBank.configuration
    context_fees = config.respond_to?(:network_fee_cents_by_context) ? config.network_fee_cents_by_context.to_h : {}

    @network_fee_cents =
      context_fees[:susu] ||
      context_fees["susu"] ||
      (config.respond_to?(:network_fee_cents_flat) ? config.network_fee_cents_flat : nil)

    @ach_fee_rate = config.stripe_ach_fee_rate if config.respond_to?(:stripe_ach_fee_rate)
    @ach_fee_cap_cents = config.stripe_ach_fee_cap_cents if config.respond_to?(:stripe_ach_fee_cap_cents)
  end

  def onboarding; end
end
RUBY

cat > app/views/layouts/susu_public.html.erb <<'ERB'
<!DOCTYPE html>
<html>
  <head>
    <title><%= content_for?(:title) ? yield(:title) : "Susu by Lightek" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="description" content="<%= content_for?(:description) ? yield(:description) : "Create and manage rotating savings circles with Susu by Lightek." %>">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "susu_public", "data-turbo-track": "reload" %>
  </head>
  <body class="susu-public">
    <header class="susu-nav">
      <%= link_to susu_path, class: "susu-logo" do %>Susu<span>.</span><% end %>
      <nav class="susu-nav-links" aria-label="Susu navigation">
        <%= link_to "How it works", susu_path(anchor: "how") %>
        <%= link_to "Features", susu_path(anchor: "features") %>
        <%= link_to "Pricing", susu_pricing_path %>
      </nav>
      <div class="susu-nav-actions">
        <%= link_to "Sign in", new_session_path, class: "btn btn-secondary" %>
        <%= link_to "Create a pool", new_susu_group_path, class: "btn btn-primary" %>
      </div>
    </header>
    <%= yield %>
    <footer class="susu-footer">
      <div><strong>Susu by Lightek</strong><p>Rotating savings circles with transparent contribution and round tracking.</p></div>
      <div class="susu-footer-links">
        <%= link_to "Home", susu_path %>
        <%= link_to "Pricing", susu_pricing_path %>
        <%= link_to "Sign in", new_session_path %>
      </div>
    </footer>
  </body>
</html>
ERB

cat > app/views/susu_public/home.html.erb <<'ERB'
<% content_for :title, "Susu by Lightek — Rotating Savings Circles" %>
<% content_for :description, "Create a rotating savings circle, set contribution rules and payout order, track rounds, and collect contributions through bank checkout." %>

<main>
  <section class="hero">
    <div class="eyebrow">SUSU BY LIGHTEK</div>
    <h1>Save together.<br><span>Take turns receiving the pool.</span></h1>
    <p>Create a rotating savings circle with people you trust. Set the contribution amount, schedule and payout order, then track every round from one place.</p>
    <div class="hero-actions">
      <%= link_to "Create your pool", new_susu_group_path, class: "btn btn-primary btn-large" %>
      <%= link_to "See how it works", susu_path(anchor: "how"), class: "btn btn-secondary btn-large" %>
    </div>
    <div class="truth-grid">
      <div><strong>Weekly</strong><span>supported schedule</span></div>
      <div><strong>Biweekly</strong><span>supported schedule</span></div>
      <div><strong>Monthly</strong><span>supported schedule</span></div>
    </div>
  </section>

  <section class="section" id="features">
    <div class="section-heading">
      <div class="eyebrow">WHAT SUSU DOES TODAY</div>
      <h2>Built around the actual circle.</h2>
      <p>The product follows groups, members, rounds, commitments and settled contributions.</p>
    </div>
    <div class="card-grid">
      <article class="feature-card"><div class="feature-icon">◎</div><h3>Rotating payout order</h3><p>Set the member order before activation so everyone can see whose round is next.</p></article>
      <article class="feature-card"><div class="feature-icon">↻</div><h3>Round-by-round tracking</h3><p>Susu tracks cycles, rounds, expected pot amounts and the amount actually settled.</p></article>
      <article class="feature-card"><div class="feature-icon">$</div><h3>Bank contribution checkout</h3><p>Members can start bank-based contribution checkout through DymondBank and Stripe ACH.</p></article>
      <article class="feature-card"><div class="feature-icon">✓</div><h3>Settlement-aware status</h3><p>A contribution is not counted complete just because checkout started. Susu waits for payment settlement state.</p></article>
      <article class="feature-card"><div class="feature-icon">≋</div><h3>Matching preferences</h3><p>Describe the contribution amount, frequency, circle size and payout you want and see compatible requests.</p></article>
      <article class="feature-card"><div class="feature-icon">◇</div><h3>Commitment tracking</h3><p>Activated circles create participant commitments tied to the cycle and reduce them as contributions settle.</p></article>
    </div>
  </section>

  <section class="section section-alt" id="how">
    <div class="section-heading"><div class="eyebrow">HOW IT WORKS</div><h2>From draft circle to funded rounds.</h2></div>
    <div class="steps">
      <article class="step"><span>01</span><div><h3>Create the circle</h3><p>Name the Susu, choose a contribution amount, select weekly, biweekly or monthly timing, and set the target member count.</p></div></article>
      <article class="step"><span>02</span><div><h3>Add members and confirm the order</h3><p>The group remains a draft until the target membership and payout positions are complete.</p></div></article>
      <article class="step"><span>03</span><div><h3>Activate the cycle</h3><p>Activation creates the cycle, participant commitments and one scheduled round for each member.</p></div></article>
      <article class="step"><span>04</span><div><h3>Contribute and track settlement</h3><p>Members use bank checkout. Settled contributions fund the current round and the dashboard shows progress toward the pot.</p></div></article>
    </div>
  </section>

  <section class="cta">
    <div><div class="eyebrow">READY TO START?</div><h2>Create the circle first. Activate it when everyone is ready.</h2><p>Susu keeps a new group in draft while you assemble members and confirm the payout order.</p></div>
    <%= link_to "Create a pool", new_susu_group_path, class: "btn btn-light btn-large" %>
  </section>
</main>
ERB

cat > app/views/susu_public/pricing.html.erb <<'ERB'
<% content_for :title, "Susu Pricing — Clear Contribution Costs" %>
<% content_for :description, "See how Susu handles pool creation and contribution checkout costs." %>

<main>
  <section class="page-hero">
    <div class="eyebrow">PRICING</div>
    <h1>Know what the system charges before you pay.</h1>
    <p>Pool setup is separate from contribution payment processing. Contribution checkout shows the payment total before the member submits it.</p>
  </section>

  <section class="section">
    <div class="pricing-grid">
      <article class="pricing-card featured">
        <div class="badge">CURRENT MODEL</div>
        <h2>Pool creation</h2>
        <div class="price">No setup fee</div>
        <p>Create a draft Susu, add members, choose the payout order and manage the circle without a separate Susu subscription charge.</p>
      </article>
      <article class="pricing-card">
        <h2>Contribution checkout</h2>
        <div class="price">Shown before payment</div>
        <p>DymondBank calculates the contribution principal and applicable payment/network costs for bank checkout. The member sees the total before payment.</p>
      </article>
    </div>

    <div class="breakdown">
      <h2>Current configured payment economics</h2>
      <div class="breakdown-grid">
        <div><strong>Your Susu contribution</strong><p>The contribution principal is tracked separately from payment/network charges.</p></div>
        <% if @network_fee_cents.present? %>
          <div><strong>Dymond network fee</strong><p><%= number_to_currency(@network_fee_cents.to_i / 100.0) %> under the server's current Susu configuration.</p></div>
        <% end %>
        <% if @ach_fee_rate.present? %>
          <div>
            <strong>ACH processor recovery</strong>
            <p>The current configuration uses <%= number_to_percentage(@ach_fee_rate.to_d * 100, precision: 2, strip_insignificant_zeros: true) %><% if @ach_fee_cap_cents.present? %> with a configured cap of <%= number_to_currency(@ach_fee_cap_cents.to_i / 100.0) %><% end %>.</p>
          </div>
        <% end %>
      </div>
      <p class="fine-print">Actual checkout is the source of truth for a specific contribution. Features and pricing not enabled in the product are not advertised here.</p>
    </div>
  </section>

  <section class="cta">
    <div><div class="eyebrow">NO SURPRISE TOTALS</div><h2>See the quote before starting bank checkout.</h2></div>
    <%= link_to "Create a pool", new_susu_group_path, class: "btn btn-light btn-large" %>
  </section>
</main>
ERB

cat > app/views/susu_public/onboarding.html.erb <<'ERB'
<% content_for :title, "Start a Susu — What You'll Configure" %>
<% content_for :description, "See the information needed to create and activate a Susu circle." %>

<main>
  <section class="page-hero">
    <div class="eyebrow">GET STARTED</div>
    <h1>Create the circle in a few clear steps.</h1>
    <p>Your circle is created as a draft and only activates after membership and payout order are ready.</p>
  </section>

  <section class="section onboarding">
    <article class="onboarding-step"><div class="step-number">1</div><div><h2>Name the circle</h2><p>Give the Susu a name so members know which circle they are joining.</p></div></article>
    <article class="onboarding-step"><div class="step-number">2</div><div><h2>Set the contribution rules</h2><p>Choose the contribution amount, target member count, and one of the supported schedules: weekly, biweekly or monthly.</p></div></article>
    <article class="onboarding-step"><div class="step-number">3</div><div><h2>Add members and payout positions</h2><p>Add existing Lightek users to the draft circle and confirm the order in which members are scheduled to receive funded rounds.</p></div></article>
    <article class="onboarding-step"><div class="step-number">4</div><div><h2>Activate when the group is ready</h2><p>Activation creates the cycle, participant commitments and scheduled rounds. Contributions then open for the current round.</p></div></article>

    <div class="onboarding-action">
      <h2>Ready to create the real one?</h2>
      <p>If you are not signed in, Lightek will ask you to authenticate before opening the Susu creation screen.</p>
      <%= link_to "Create my Susu", new_susu_group_path, class: "btn btn-primary btn-large" %>
    </div>
  </section>
</main>
ERB

cat > app/assets/stylesheets/susu_public.css <<'CSS'
:root{--susu-teal:#00d4aa;--susu-purple:#7c3aed;--susu-dark:#0a0a0a;--susu-gray:#555;--susu-line:#e7e7e7;--susu-soft:#f7f8f8}
*{box-sizing:border-box}html{scroll-behavior:smooth}body.susu-public{margin:0;color:var(--susu-dark);background:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;line-height:1.6}a{color:inherit}
.susu-nav{position:sticky;top:0;z-index:20;min-height:72px;padding:0 5%;display:flex;align-items:center;gap:2rem;justify-content:space-between;background:rgba(255,255,255,.96);border-bottom:1px solid var(--susu-line);backdrop-filter:blur(10px)}
.susu-logo{text-decoration:none;font-size:1.5rem;font-weight:800;letter-spacing:-.04em}.susu-logo span{color:var(--susu-teal)}.susu-nav-links,.susu-nav-actions{display:flex;align-items:center;gap:1rem}.susu-nav-links a{text-decoration:none;color:var(--susu-gray);font-size:.92rem}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:44px;padding:.72rem 1.15rem;border-radius:8px;border:1px solid transparent;text-decoration:none;font-weight:750}.btn-primary{background:var(--susu-teal);color:var(--susu-dark)}.btn-secondary{border-color:var(--susu-dark);background:#fff}.btn-light{background:#fff;color:var(--susu-dark)}.btn-large{min-height:52px;padding:.9rem 1.45rem}
.hero{padding:7rem 5% 5rem;text-align:center;background:linear-gradient(135deg,rgba(0,212,170,.10),rgba(124,58,237,.07))}.hero h1,.page-hero h1{max-width:900px;margin:.5rem auto 1rem;font-size:clamp(2.7rem,7vw,5.5rem);line-height:.98;letter-spacing:-.06em}.hero h1 span{color:var(--susu-teal)}.hero>p,.page-hero p{max-width:700px;margin:0 auto 2rem;color:var(--susu-gray);font-size:1.08rem}.hero-actions{display:flex;justify-content:center;gap:1rem;flex-wrap:wrap}.eyebrow{font-size:.75rem;font-weight:800;letter-spacing:.18em;color:var(--susu-purple)}
.truth-grid{max-width:850px;margin:4rem auto 0;border-top:1px solid var(--susu-line);padding-top:2rem;display:grid;grid-template-columns:repeat(3,1fr)}.truth-grid div{display:flex;flex-direction:column;gap:.25rem}.truth-grid strong{font-size:1.35rem}.truth-grid span{color:var(--susu-gray);font-size:.85rem}
.section{max-width:1200px;margin:0 auto;padding:6rem 5%}.section-alt{max-width:none;background:var(--susu-soft)}.section-alt>*{max-width:1100px;margin-left:auto;margin-right:auto}.section-heading{max-width:720px;margin-bottom:3rem}.section-heading h2{margin:.5rem 0;font-size:clamp(2rem,5vw,3.4rem);letter-spacing:-.04em}.section-heading p{color:var(--susu-gray)}
.card-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1.25rem}.feature-card,.pricing-card{padding:2rem;border:1px solid var(--susu-line);border-radius:16px;background:#fff}.feature-icon{font-size:2rem;color:var(--susu-teal);font-weight:800}.feature-card h3{margin-bottom:.5rem}.feature-card p,.pricing-card p{color:var(--susu-gray);margin-bottom:0}
.steps{display:grid;gap:1rem}.step{display:grid;grid-template-columns:90px 1fr;gap:1.25rem;padding:1.5rem 0;border-bottom:1px solid var(--susu-line)}.step>span{color:var(--susu-purple);font-size:2.2rem;font-weight:800}.step h3{margin:0 0 .35rem}.step p{margin:0;color:var(--susu-gray)}
.page-hero{padding:5rem 5% 2rem;text-align:center}.page-hero h1{font-size:clamp(2.5rem,6vw,4.5rem)}
.pricing-grid{display:grid;grid-template-columns:1fr 1fr;gap:1.25rem}.pricing-card.featured{border-color:var(--susu-teal)}.badge{display:inline-block;font-size:.7rem;letter-spacing:.14em;font-weight:800;color:var(--susu-purple)}.price{margin:1rem 0;font-size:2rem;font-weight:850;color:var(--susu-teal)}
.breakdown{margin-top:2rem;padding:2rem;background:var(--susu-soft);border-radius:16px}.breakdown-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:1rem}.breakdown-grid>div{background:#fff;padding:1.5rem;border-radius:12px;border:1px solid var(--susu-line)}.breakdown-grid p,.fine-print{color:var(--susu-gray);font-size:.92rem}
.onboarding{max-width:900px}.onboarding-step{display:grid;grid-template-columns:64px 1fr;gap:1.25rem;padding:1.5rem 0;border-bottom:1px solid var(--susu-line)}.step-number{width:48px;height:48px;border-radius:50%;display:grid;place-items:center;background:var(--susu-teal);font-weight:850}.onboarding-step h2{margin:0 0 .35rem}.onboarding-step p{color:var(--susu-gray);margin:0}.onboarding-action{margin-top:3rem;padding:2.5rem;border-radius:16px;background:var(--susu-soft);text-align:center}
.cta{padding:4rem 5%;display:flex;align-items:center;justify-content:space-between;gap:2rem;color:#fff;background:linear-gradient(135deg,var(--susu-teal),var(--susu-purple))}.cta h2{margin:.4rem 0;font-size:clamp(2rem,4vw,3.2rem);max-width:750px}.cta p{max-width:700px}
.susu-footer{padding:3rem 5%;display:flex;justify-content:space-between;gap:2rem;color:#fff;background:var(--susu-dark)}.susu-footer p{color:#aaa}.susu-footer-links{display:flex;gap:1rem;align-items:flex-start}.susu-footer-links a{color:var(--susu-teal);text-decoration:none}
@media(max-width:820px){.susu-nav-links{display:none}.susu-nav{flex-wrap:wrap;padding-top:.75rem;padding-bottom:.75rem}.card-grid,.pricing-grid,.breakdown-grid,.truth-grid{grid-template-columns:1fr}.cta,.susu-footer{flex-direction:column;align-items:flex-start}}
CSS

python3 <<'PY'
from pathlib import Path
path = Path("config/routes.rb")
src = path.read_text()

if 'get "susu", to: "susu_public#home", as: :susu' not in src:
    block = """
# ── Susu public product surface ───────────────────────────────────────────────
get "susu",            to: "susu_public#home",       as: :susu
get "susu/pricing",    to: "susu_public#pricing",    as: :susu_pricing
get "susu/onboarding", to: "susu_public#onboarding", as: :susu_onboarding

"""
    if '# ── Gatekeeper' in src:
        src = src.replace('# ── Gatekeeper', block + '# ── Gatekeeper', 1)
    elif 'root "pages#home"' in src:
        src = src.replace('root "pages#home"', 'root "pages#home"\n' + block, 1)
    else:
        raise SystemExit("ERROR: no safe route insertion anchor found")
    path.write_text(src)
    print("Added Susu public routes.")
else:
    print("Susu public routes already present.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/controllers/susu_public_controller.rb

echo
echo "=== ROUTES ==="
bin/rails routes | grep -E '/susu($|/)' | head -80

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== LEGACY CLAIM CHECK ==="
if grep -RniE 'international|cross-border|borderless|immutable|freeze or seize|advance payout|under 24 hours|1\.2%|1\.5%|no middleman' app/views/susu_public; then
  echo "ERROR: unsupported legacy marketing claim remains." >&2
  exit 1
else
  echo "No unsupported legacy marketing claims found."
fi

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== STATUS ==="
git status --short

echo
echo "DONE"
echo "Backup: $BACKUP"
echo "Public URLs: /susu  /susu/pricing  /susu/onboarding"
