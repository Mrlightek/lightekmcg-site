DymondDash.configure do |config|
  # ── Fallback values (DB record wins on every request) ─────────────────────────
  config.app_name_fallback    = "Lightek MCG"
  config.tagline_fallback     = "Leader In Gathering Helpful Technical Engineering Knowledge"
  config.default_theme_slug   = :dark_gold

  # ── Auth — points to ApplicationController#current_user ──────────────────────
  config.current_user_method  = :current_user

  # ── Private gem server (set in production via env) ────────────────────────────
  # config.gem_server_url = ENV["DYMOND_GEM_SERVER_URL"]

  # ── Docker deploy webhook ─────────────────────────────────────────────────────
  # config.deploy_webhook_url = ENV["DYMOND_DEPLOY_WEBHOOK_URL"]

  # ── Feature flags ─────────────────────────────────────────────────────────────
  config.marketplace_enabled         = true
  config.theme_customisation_enabled = true
  config.nav_reorder_enabled         = true
end

# Seed DymondDash defaults on first boot in development
Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.table_exists?("dymond_dash_themes")
    DymondDash::Seeds.run if DymondDash::Theme.count.zero?
  end
rescue StandardError
  nil
end
