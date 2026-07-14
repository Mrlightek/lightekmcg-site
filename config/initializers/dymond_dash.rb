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

# Seed DymondDash defaults on first boot (idempotent; only when empty).
# Checks canonical admin themes — the legacy dymond_dash_themes table was
# consolidated into dymond_theme_themes.
Rails.application.config.after_initialize do
  if defined?(DymondTheme::Theme) &&
     DymondTheme::Theme.where(scope: "admin").count.zero?
    DymondDash::Seeds.run
  end
rescue StandardError => e
  Rails.logger.warn "[DymondDash] boot seed skipped: #{e.message}" if defined?(Rails) && Rails.logger
end
