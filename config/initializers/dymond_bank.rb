DymondBank.configure do |config|
  # ── Plaid (set via environment variables) ─────────────────────────────────────
  config.plaid_client_id_env   = "PLAID_CLIENT_ID"
  config.plaid_secret_env      = "PLAID_SECRET"
  config.plaid_webhook_url     = ENV["PLAID_WEBHOOK_URL"]    # https://lightekmcg.com/billing/webhooks/plaid
  config.default_processor     = :plaid

  # ── Platform settings ─────────────────────────────────────────────────────────
  config.platform_fee_rate     = 0.0          # no platform cut initially
  config.savings_apy           = 4.85
  config.default_currency      = "usd"

  # ── Company details for invoice PDFs ─────────────────────────────────────────
  config.company_name          = "Lightek MCG"
  config.company_email         = "billing@lightekmcg.com"
  config.company_address       = "Kissimmee, FL"

  # ── Billing behavior ──────────────────────────────────────────────────────────
  config.auto_charge_enabled        = true
  config.invoice_grace_period_days  = 7

  # ── Cron schedules ────────────────────────────────────────────────────────────
  config.revenue_engine_schedule    = "0 6 * * *"   # daily 6am
  config.usage_aggregation_schedule = "0 * * * *"   # hourly
end

# Seed subscription plans on first boot in development
Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.table_exists?("dymond_bank_subscription_plans")
    DymondBank::Seeds.run if DymondBank::SubscriptionPlan.count.zero?
  end
rescue StandardError
  nil
end
