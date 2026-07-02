source "https://rubygems.org"

gem "rails", "~> 8.0.4"

# ── Asset pipeline ─────────────────────────────────────────────────────────────
gem "propshaft"

# ── Database — PostgreSQL required for jsonb columns in ecosystem gems ─────────
gem "pg", ">= 1.5"

# ── Web server ─────────────────────────────────────────────────────────────────
gem "puma", ">= 5.0"

# ── Frontend ───────────────────────────────────────────────────────────────────
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# ── Auth & authorization ───────────────────────────────────────────────────────
# Rails 8 native auth — no Devise
gem "bcrypt",    "~> 3.1.7"      # has_secure_password
gem "cancancan", "~> 3.6"        # ability-based authorization

# ── Background jobs ────────────────────────────────────────────────────────────
gem "sidekiq",      ">= 7.0"     # replaces SolidQueue for ecosystem gem compat
gem "sidekiq-cron", "~> 1.12"    # scheduled jobs (revenue engine, usage aggregator)
gem "redis",        "~> 5.0"     # Sidekiq + ActionCable backend

# ── Caching ────────────────────────────────────────────────────────────────────
gem "solid_cache"                # keep for Rails.cache (DB-backed)

# ── ActionCable ────────────────────────────────────────────────────────────────
gem "solid_cable"                # keep for ActionCable (or swap to Redis adapter)

# ── File storage ──────────────────────────────────────────────────────────────
gem "aws-sdk-s3",       require: false   # S3-compatible (MinIO in production)
gem "image_processing", "~> 1.2"

# ── Money — must be in host app for monetize macro ────────────────────────────
gem "money-rails", "~> 1.15"

# ── Pagination ────────────────────────────────────────────────────────────────
gem "kaminari", "~> 1.2"

# ── HTTP ──────────────────────────────────────────────────────────────────────
gem "faraday", "~> 2.0"

# ── Encryption (Plaid access tokens at rest) ─────────────────────────────────
gem "lockbox",   "~> 1.3"   # column-level encryption
gem "blind_index"            # encrypted column searching if needed

# ── PDF (invoices) ────────────────────────────────────────────────────────────
gem "prawn",       "~> 2.5"
gem "prawn-table", "~> 0.2"

# ── Deployment ────────────────────────────────────────────────────────────────
gem "kamal",    require: false
gem "thruster", require: false
gem "bootsnap", require: false

# ── Timezone data ─────────────────────────────────────────────────────────────
gem "tzinfo-data", platforms: %i[windows jruby]

# ══════════════════════════════════════════════════════════════════════════════
# Dymond / Lightek ecosystem gems
# In development: path references. In production: private gem server.
# ══════════════════════════════════════════════════════════════════════════════

# Core infrastructure
gem "dymond_dash", git: "git@github.com:lightekmcg/dymond_dash.git"       # CMS dashboard engine — mount first
gem "dymond_bank", git: "git@github.com:lightekmcg/dymond_bank.git"       # Billing & financial layer
gem "dymond_site", git: "git@github.com:lightekmcg/dymond_site.git"       # CMS engine shell

# Add remaining gems as you complete them:
gem "dymond_theme", git: "git@github.com:lightekmcg/dymond_theme.git" 
gem "dymond_compute", git: "git@github.com:lightekmcg/dymond_compute.git"
# gem "dymond_core", git: "git@github.com:lightekmcg/dymond_core"
# gem "dymond_social", git: "git@github.com:lightekmcg/dymond_social"
# gem "dymond_safety", git: "git@github.com:lightekmcg/dymond_safety"
# gem "lightek_core", git: "git@github.com:lightekmcg/lightek_core"
# gem "lightek_studio", git: "git@github.com:lightekmcg/lightek_studio"

# ── Development & test ─────────────────────────────────────────────────────────
group :development, :test do
  gem "debug",    platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails",       "~> 6.0"
  gem "factory_bot_rails", "~> 6.0"
end

group :development do
  gem "web-console"
  gem "letter_opener"    # preview emails in browser
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "shoulda-matchers"
end
gem "dotenv-rails", "~> 3.2"
