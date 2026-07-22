# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_07_22_191817) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "architectures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "catalogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dymond_bank_accounts", force: :cascade do |t|
    t.string "accountable_type", null: false
    t.bigint "accountable_id", null: false
    t.string "account_type", default: "checking", null: false
    t.string "status", default: "active", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "balance_cents", default: 0, null: false
    t.bigint "available_cents", default: 0, null: false
    t.bigint "credit_limit_cents"
    t.string "display_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accountable_type", "accountable_id"], name: "idx_on_accountable_type_accountable_id_ab68425a01"
  end

  create_table "dymond_bank_credit_lines", force: :cascade do |t|
    t.string "borrower_type", null: false
    t.bigint "borrower_id", null: false
    t.string "status", default: "pending", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "limit_cents", null: false
    t.bigint "drawn_cents", default: 0, null: false
    t.decimal "interest_rate", precision: 5, scale: 4, default: "0.0"
    t.date "approved_at"
    t.date "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["borrower_type", "borrower_id"], name: "idx_on_borrower_type_borrower_id_bd9cc06bc0"
  end

  create_table "dymond_bank_customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.string "company"
    t.bigint "user_id"
    t.jsonb "address", default: {}
    t.string "status", default: "active", null: false
    t.text "notes"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_dymond_bank_customers_on_email"
    t.index ["status"], name: "index_dymond_bank_customers_on_status"
    t.index ["user_id"], name: "index_dymond_bank_customers_on_user_id"
  end

  create_table "dymond_bank_invoice_line_items", force: :cascade do |t|
    t.bigint "invoice_id", null: false
    t.string "description", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "unit_price_cents", null: false
    t.string "currency", default: "usd", null: false
    t.string "item_type"
    t.string "reference_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id"], name: "index_dymond_bank_invoice_line_items_on_invoice_id"
  end

  create_table "dymond_bank_invoices", force: :cascade do |t|
    t.string "billable_type", null: false
    t.bigint "billable_id", null: false
    t.bigint "linked_account_id"
    t.string "number"
    t.string "status", default: "draft", null: false
    t.string "invoice_type", default: "manual", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "discount_cents", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.bigint "amount_paid_cents", default: 0, null: false
    t.bigint "amount_remaining_cents", default: 0, null: false
    t.bigint "platform_fee_cents", default: 0, null: false
    t.text "memo"
    t.date "due_date"
    t.datetime "finalized_at"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billable_type", "billable_id"], name: "index_dymond_bank_invoices_on_billable_type_and_billable_id"
    t.index ["due_date"], name: "index_dymond_bank_invoices_on_due_date"
    t.index ["linked_account_id"], name: "index_dymond_bank_invoices_on_linked_account_id"
    t.index ["number"], name: "index_dymond_bank_invoices_on_number", unique: true, where: "(number IS NOT NULL)"
    t.index ["status"], name: "index_dymond_bank_invoices_on_status"
  end

  create_table "dymond_bank_ledger_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "direction", null: false
    t.bigint "amount_cents", null: false
    t.string "currency", default: "usd", null: false
    t.string "memo"
    t.string "reference"
    t.bigint "running_balance_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_dymond_bank_ledger_entries_on_account_id"
    t.index ["reference"], name: "index_dymond_bank_ledger_entries_on_reference"
  end

  create_table "dymond_bank_linked_accounts", force: :cascade do |t|
    t.string "linkable_type", null: false
    t.bigint "linkable_id", null: false
    t.string "processor", default: "plaid", null: false
    t.string "access_token", null: false
    t.string "processor_account_id", null: false
    t.string "plaid_item_id"
    t.string "routing_number"
    t.string "account_last4"
    t.string "account_subtype"
    t.string "institution_name"
    t.string "display_name"
    t.string "status", default: "pending", null: false
    t.boolean "is_default", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["linkable_type", "linkable_id"], name: "idx_on_linkable_type_linkable_id_ba99cb63a1"
    t.index ["plaid_item_id"], name: "index_dymond_bank_linked_accounts_on_plaid_item_id"
    t.index ["status"], name: "index_dymond_bank_linked_accounts_on_status"
  end

  create_table "dymond_bank_offers", force: :cascade do |t|
    t.string "offerable_type"
    t.bigint "offerable_id"
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.string "mode", default: "paid", null: false
    t.bigint "setup_fee_cents"
    t.bigint "subscription_plan_id"
    t.string "billing_period", default: "customer_choice", null: false
    t.boolean "usage_billing", default: false, null: false
    t.integer "trial_days"
    t.string "currency", default: "usd", null: false
    t.boolean "active", default: true, null: false
    t.integer "sort_order", default: 0
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_dymond_bank_offers_on_active"
    t.index ["offerable_type", "offerable_id"], name: "idx_dymond_bank_offers_offerable"
    t.index ["slug"], name: "index_dymond_bank_offers_on_slug", unique: true
    t.index ["subscription_plan_id"], name: "index_dymond_bank_offers_on_subscription_plan_id"
  end

  create_table "dymond_bank_payouts", force: :cascade do |t|
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.bigint "account_id"
    t.bigint "linked_account_id"
    t.string "status", default: "pending", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "amount_cents", null: false
    t.bigint "fee_cents", default: 0, null: false
    t.string "description"
    t.string "processor_ref"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_dymond_bank_payouts_on_account_id"
    t.index ["linked_account_id"], name: "index_dymond_bank_payouts_on_linked_account_id"
    t.index ["recipient_type", "recipient_id"], name: "index_dymond_bank_payouts_on_recipient_type_and_recipient_id"
    t.index ["status"], name: "index_dymond_bank_payouts_on_status"
  end

  create_table "dymond_bank_platforms", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dymond_bank_purchases", force: :cascade do |t|
    t.bigint "offer_id", null: false
    t.string "customer_type", null: false
    t.bigint "customer_id", null: false
    t.bigint "invoice_id"
    t.bigint "subscription_id"
    t.string "status", default: "pending", null: false
    t.string "mode"
    t.string "billing_interval"
    t.bigint "amount_cents", default: 0, null: false
    t.string "currency", default: "usd", null: false
    t.jsonb "provision_spec", default: {}
    t.bigint "work_item_id"
    t.datetime "provisioned_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "instance_id"
    t.string "instance_host"
    t.index ["customer_type", "customer_id"], name: "idx_dymond_bank_purchases_customer"
    t.index ["instance_id"], name: "index_dymond_bank_purchases_on_instance_id"
    t.index ["invoice_id"], name: "index_dymond_bank_purchases_on_invoice_id"
    t.index ["offer_id"], name: "index_dymond_bank_purchases_on_offer_id"
    t.index ["status"], name: "index_dymond_bank_purchases_on_status"
    t.index ["subscription_id"], name: "index_dymond_bank_purchases_on_subscription_id"
  end

  create_table "dymond_bank_revenue_events", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "event_type", null: false
    t.string "status", default: "open", null: false
    t.bigint "potential_cents", default: 0
    t.string "currency", default: "usd", null: false
    t.text "description"
    t.jsonb "metadata_json"
    t.datetime "actioned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_dymond_bank_revenue_events_on_event_type"
    t.index ["status"], name: "index_dymond_bank_revenue_events_on_status"
    t.index ["subject_type", "subject_id"], name: "idx_on_subject_type_subject_id_a6fc18713e"
  end

  create_table "dymond_bank_royalty_payments", force: :cascade do |t|
    t.bigint "royalty_split_id", null: false
    t.bigint "source_transaction_id", null: false
    t.bigint "payout_id"
    t.string "currency", default: "usd", null: false
    t.bigint "gross_cents", null: false
    t.bigint "net_cents", null: false
    t.bigint "fee_cents", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_id"], name: "index_dymond_bank_royalty_payments_on_payout_id"
    t.index ["royalty_split_id"], name: "index_dymond_bank_royalty_payments_on_royalty_split_id"
    t.index ["source_transaction_id"], name: "index_dymond_bank_royalty_payments_on_source_transaction_id"
  end

  create_table "dymond_bank_royalty_splits", force: :cascade do |t|
    t.string "splittable_type", null: false
    t.bigint "splittable_id", null: false
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.decimal "percentage", precision: 5, scale: 2
    t.boolean "active", default: true
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "split_type", default: "percentage", null: false
    t.bigint "fixed_amount_cents"
    t.integer "position", default: 0, null: false
    t.index ["split_type"], name: "index_dymond_bank_royalty_splits_on_split_type"
    t.index ["splittable_type", "splittable_id"], name: "idx_on_splittable_type_splittable_id_09428d710e"
  end

  create_table "dymond_bank_subscription_plans", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.text "description"
    t.bigint "price_monthly_cents", default: 0, null: false
    t.bigint "price_annual_cents", default: 0, null: false
    t.string "currency", default: "usd", null: false
    t.boolean "active", default: true
    t.integer "sort_order", default: 0
    t.jsonb "features_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_dymond_bank_subscription_plans_on_slug", unique: true
  end

  create_table "dymond_bank_subscriptions", force: :cascade do |t|
    t.string "subscriber_type", null: false
    t.bigint "subscriber_id", null: false
    t.bigint "plan_id", null: false
    t.bigint "linked_account_id"
    t.string "status", default: "trialing", null: false
    t.string "billing_interval", default: "monthly", null: false
    t.string "processor_ref"
    t.datetime "trial_ends_at"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["linked_account_id"], name: "index_dymond_bank_subscriptions_on_linked_account_id"
    t.index ["plan_id"], name: "index_dymond_bank_subscriptions_on_plan_id"
    t.index ["subscriber_type", "subscriber_id"], name: "idx_on_subscriber_type_subscriber_id_1192f8aceb"
  end

  create_table "dymond_bank_transactions", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "invoice_id"
    t.string "transaction_type", null: false
    t.string "status", default: "pending", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "amount_cents", null: false
    t.bigint "fee_cents", default: 0, null: false
    t.bigint "net_cents", default: 0, null: false
    t.string "processor_name"
    t.string "processor_ref"
    t.string "idempotency_key"
    t.text "failure_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "payout_id"
    t.index ["account_id"], name: "index_dymond_bank_transactions_on_account_id"
    t.index ["idempotency_key"], name: "index_dymond_bank_transactions_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["invoice_id"], name: "index_dymond_bank_transactions_on_invoice_id"
    t.index ["payout_id"], name: "index_dymond_bank_transactions_on_payout_id"
    t.index ["processor_ref"], name: "index_dymond_bank_transactions_on_processor_ref"
    t.index ["status"], name: "index_dymond_bank_transactions_on_status"
  end

  create_table "dymond_bank_usage_charges", force: :cascade do |t|
    t.string "chargeable_type", null: false
    t.bigint "chargeable_id", null: false
    t.bigint "invoice_id"
    t.string "meter", null: false
    t.decimal "total_quantity", precision: 12, scale: 4, null: false
    t.bigint "total_cents", null: false
    t.string "currency", default: "usd", null: false
    t.date "period_start"
    t.date "period_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chargeable_type", "chargeable_id"], name: "idx_on_chargeable_type_chargeable_id_ba297a9f02"
  end

  create_table "dymond_bank_usage_rates", force: :cascade do |t|
    t.string "meter", null: false
    t.string "plan_slug", default: "starter", null: false
    t.bigint "rate_per_unit_cents", default: 0, null: false
    t.string "currency", default: "usd", null: false
    t.string "unit_label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["meter", "plan_slug"], name: "index_dymond_bank_usage_rates_on_meter_and_plan_slug", unique: true
  end

  create_table "dymond_bank_usage_records", force: :cascade do |t|
    t.string "metered_type", null: false
    t.bigint "metered_id", null: false
    t.bigint "usage_charge_id"
    t.string "meter", null: false
    t.decimal "quantity", precision: 12, scale: 4, null: false
    t.string "source_reference"
    t.boolean "billed", default: false
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billed"], name: "index_dymond_bank_usage_records_on_billed"
    t.index ["meter"], name: "index_dymond_bank_usage_records_on_meter"
    t.index ["metered_type", "metered_id"], name: "index_dymond_bank_usage_records_on_metered_type_and_metered_id"
  end

  create_table "dymond_catalog_products", force: :cascade do |t|
    t.string "sku", null: false
    t.string "name", null: false
    t.string "department"
    t.string "icon"
    t.string "color"
    t.bigint "wholesale_price_cents", default: 0, null: false
    t.text "description"
    t.boolean "ministry_engine", default: false, null: false
    t.jsonb "includes_json"
    t.jsonb "specs_json"
    t.boolean "active", default: true, null: false
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_dymond_catalog_products_on_active"
    t.index ["sku"], name: "index_dymond_catalog_products_on_sku", unique: true
  end

  create_table "dymond_compute_assets", force: :cascade do |t|
    t.string "filename"
    t.string "content_type"
    t.bigint "byte_size"
    t.string "kind"
    t.string "purpose"
    t.string "alt_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "transcode_status"
    t.string "hls_key"
    t.text "transcode_error"
    t.jsonb "transcode_meta", default: {}
    t.index ["kind"], name: "index_dymond_compute_assets_on_kind"
    t.index ["purpose"], name: "index_dymond_compute_assets_on_purpose"
  end

  create_table "dymond_compute_prayer_schedules", force: :cascade do |t|
    t.string "job_class", null: false
    t.string "prayer", null: false
    t.integer "offset_seconds", default: 0
    t.boolean "recurring", default: true
    t.string "tenant_key"
    t.jsonb "job_args", default: []
    t.boolean "active", default: true
    t.datetime "last_enqueued_at"
    t.datetime "fires_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active", "recurring"], name: "index_dymond_compute_prayer_schedules_on_active_and_recurring"
    t.index ["tenant_key"], name: "index_dymond_compute_prayer_schedules_on_tenant_key"
  end

  create_table "dymond_dash_account_plans", force: :cascade do |t|
    t.string "plan_slug", default: "starter", null: false
    t.string "status", default: "active", null: false
    t.datetime "trial_ends_at"
    t.bigint "account_id"
    t.string "account_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_type", "account_id"], name: "index_dymond_dash_account_plans_on_account_type_and_account_id"
  end

  create_table "dymond_dash_app_configs", force: :cascade do |t|
    t.string "app_name", default: "Dymond CMS", null: false
    t.string "tagline"
    t.string "logo_url"
    t.string "favicon_url"
    t.bigint "theme_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "logo_asset_id"
    t.string "support_email"
    t.string "time_zone"
    t.string "date_format"
    t.string "default_locale"
    t.string "cdn_base_url"
    t.string "transcode_runner"
    t.index ["theme_id"], name: "index_dymond_dash_app_configs_on_theme_id"
  end

  create_table "dymond_dash_ecosystem_gems", force: :cascade do |t|
    t.string "slug", null: false
    t.string "display_name", null: false
    t.text "description"
    t.string "category"
    t.string "rubygems_name", null: false
    t.string "repo_url"
    t.string "current_version"
    t.string "min_plan_required", default: "starter"
    t.string "icon"
    t.jsonb "dependencies_json"
    t.boolean "featured", default: false
    t.boolean "core", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_dymond_dash_ecosystem_gems_on_slug", unique: true
  end

  create_table "dymond_dash_features", force: :cascade do |t|
    t.string "slug", null: false
    t.string "label", null: false
    t.string "icon"
    t.string "gem_source"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_dymond_dash_features_on_slug", unique: true
  end

  create_table "dymond_dash_installed_gems", force: :cascade do |t|
    t.bigint "ecosystem_gem_id", null: false
    t.string "installed_version"
    t.string "status", default: "pending", null: false
    t.text "install_log"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ecosystem_gem_id"], name: "index_dymond_dash_installed_gems_on_ecosystem_gem_id"
    t.index ["status"], name: "index_dymond_dash_installed_gems_on_status"
  end

  create_table "dymond_dash_nav_items", force: :cascade do |t|
    t.bigint "section_id", null: false
    t.string "label", null: false
    t.string "icon", null: false
    t.string "path_helper", null: false
    t.string "badge_method"
    t.string "feature_slug"
    t.integer "position", default: 0
    t.boolean "visible", default: true
    t.jsonb "roles_json"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["section_id"], name: "index_dymond_dash_nav_items_on_section_id"
  end

  create_table "dymond_dash_nav_sections", force: :cascade do |t|
    t.string "label", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_dymond_dash_nav_sections_on_slug", unique: true
  end

  create_table "dymond_dash_notifications", force: :cascade do |t|
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "category", default: "system", null: false
    t.string "title", null: false
    t.text "body"
    t.string "url"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["read_at"], name: "index_dymond_dash_notifications_on_read_at"
    t.index ["recipient_type", "recipient_id"], name: "idx_on_recipient_type_recipient_id_9cf999bace"
    t.index ["subject_type", "subject_id"], name: "index_dymond_dash_notifications_on_subject_type_and_subject_id"
  end

  create_table "dymond_dash_pending_gemfile_changes", force: :cascade do |t|
    t.bigint "ecosystem_gem_id", null: false
    t.string "action", null: false
    t.string "gem_name", null: false
    t.string "gem_version"
    t.boolean "applied", default: false, null: false
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["applied"], name: "index_dymond_dash_pending_gemfile_changes_on_applied"
    t.index ["ecosystem_gem_id"], name: "index_dymond_dash_pending_gemfile_changes_on_ecosystem_gem_id"
  end

  create_table "dymond_dash_plan_features", force: :cascade do |t|
    t.string "plan_slug", null: false
    t.string "feature_slug", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_slug", "feature_slug"], name: "index_dymond_dash_plan_features_on_plan_slug_and_feature_slug", unique: true
  end

  create_table "dymond_dispatch_work_items", force: :cascade do |t|
    t.string "handler", null: false
    t.jsonb "args", default: []
    t.string "queue", default: "default", null: false
    t.integer "priority", default: 5, null: false
    t.string "status", default: "queued", null: false
    t.string "worker_id"
    t.jsonb "dispositions", default: []
    t.jsonb "result", default: {}
    t.text "error"
    t.integer "attempts", default: 0, null: false
    t.datetime "run_at"
    t.datetime "enqueued_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string "tenant_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.string "kind", default: "job", null: false
    t.index ["enqueued_at"], name: "index_dymond_dispatch_work_items_on_enqueued_at"
    t.index ["kind", "status"], name: "idx_dispatch_work_items_kind_status"
    t.index ["kind"], name: "index_dymond_dispatch_work_items_on_kind"
    t.index ["run_at"], name: "index_dymond_dispatch_work_items_on_run_at"
    t.index ["status", "queue"], name: "index_dymond_dispatch_work_items_on_status_and_queue"
    t.index ["subject_type", "subject_id"], name: "idx_dispatch_work_items_subject"
    t.index ["tenant_key"], name: "index_dymond_dispatch_work_items_on_tenant_key"
  end

  create_table "dymond_kb_articles", force: :cascade do |t|
    t.bigint "topic_id", null: false
    t.string "article_id", null: false
    t.string "title", null: false
    t.string "article_type", default: "guide", null: false
    t.text "excerpt"
    t.text "body"
    t.integer "read_minutes", default: 5
    t.boolean "featured", default: false, null: false
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_dymond_kb_articles_on_article_id", unique: true
    t.index ["featured"], name: "index_dymond_kb_articles_on_featured"
    t.index ["topic_id"], name: "index_dymond_kb_articles_on_topic_id"
  end

  create_table "dymond_kb_topics", force: :cascade do |t|
    t.string "name", null: false
    t.string "topic_id", null: false
    t.string "icon"
    t.string "color"
    t.text "description"
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["topic_id"], name: "index_dymond_kb_topics_on_topic_id", unique: true
  end

  create_table "dymond_site_footers", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.jsonb "columns", default: []
    t.string "copyright"
    t.string "tagline"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_dymond_site_footers_on_site_id"
  end

  create_table "dymond_site_nav_items", force: :cascade do |t|
    t.bigint "nav_menu_id", null: false
    t.bigint "parent_id"
    t.bigint "page_id"
    t.string "label", null: false
    t.string "external_url"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nav_menu_id"], name: "index_dymond_site_nav_items_on_nav_menu_id"
    t.index ["page_id"], name: "index_dymond_site_nav_items_on_page_id"
    t.index ["parent_id"], name: "index_dymond_site_nav_items_on_parent_id"
  end

  create_table "dymond_site_nav_menus", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", default: "Main Menu"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_dymond_site_nav_menus_on_site_id"
  end

  create_table "dymond_site_pages", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "title", null: false
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "theme_id"
    t.index ["site_id", "position"], name: "index_dymond_site_pages_on_site_id_and_position"
    t.index ["site_id", "slug"], name: "index_dymond_site_pages_on_site_id_and_slug", unique: true
    t.index ["site_id"], name: "index_dymond_site_pages_on_site_id"
    t.index ["theme_id"], name: "index_dymond_site_pages_on_theme_id"
  end

  create_table "dymond_site_sections", force: :cascade do |t|
    t.bigint "page_id", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "theme_id"
    t.index ["page_id", "position"], name: "index_dymond_site_sections_on_page_id_and_position"
    t.index ["page_id"], name: "index_dymond_site_sections_on_page_id"
    t.index ["theme_id"], name: "index_dymond_site_sections_on_theme_id"
  end

  create_table "dymond_site_site_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "key", null: false
    t.string "description"
    t.jsonb "settings", default: {}
    t.boolean "preset", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_dymond_site_site_templates_on_key", unique: true
  end

  create_table "dymond_site_sites", force: :cascade do |t|
    t.string "name", null: false
    t.string "host", null: false
    t.bigint "active_theme_id"
    t.string "tenant_type"
    t.bigint "tenant_id"
    t.jsonb "manifest", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "active_template_id"
    t.index ["active_template_id"], name: "index_dymond_site_sites_on_active_template_id"
    t.index ["active_theme_id"], name: "index_dymond_site_sites_on_active_theme_id"
    t.index ["host"], name: "index_dymond_site_sites_on_host", unique: true
    t.index ["tenant_type", "tenant_id"], name: "index_dymond_site_sites_on_tenant_type_and_tenant_id"
  end

  create_table "dymond_studio_media_assets", force: :cascade do |t|
    t.bigint "asset_id", null: false
    t.string "title"
    t.string "status", default: "uploaded", null: false
    t.jsonb "pipeline_log", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["asset_id"], name: "index_dymond_studio_media_assets_on_asset_id"
    t.index ["status"], name: "index_dymond_studio_media_assets_on_status"
  end

  create_table "dymond_theme_themes", force: :cascade do |t|
    t.string "name", null: false
    t.string "scope", default: "site", null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.jsonb "tokens", default: {}, null: false
    t.text "custom_css"
    t.jsonb "templates", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "preset", default: false, null: false
    t.index ["owner_type", "owner_id"], name: "index_dymond_theme_themes_on_owner_type_and_owner_id"
    t.index ["preset"], name: "index_dymond_theme_themes_on_preset"
    t.index ["scope"], name: "index_dymond_theme_themes_on_scope"
  end

  create_table "homes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "marlon_blueprint_concerns", force: :cascade do |t|
    t.bigint "feature_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "target_type", default: "model", null: false
    t.string "implementation_class"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_id", "key"], name: "idx_marlon_concerns_feature_key", unique: true
    t.index ["feature_id"], name: "index_marlon_blueprint_concerns_on_feature_id"
  end

  create_table "marlon_capability_pack_dependencies", force: :cascade do |t|
    t.bigint "capability_pack_id", null: false
    t.bigint "dependency_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capability_pack_id", "dependency_id"], name: "idx_marlon_pack_dependencies_unique", unique: true
  end

  create_table "marlon_capability_pack_features", force: :cascade do |t|
    t.bigint "capability_pack_id", null: false
    t.bigint "feature_id", null: false
    t.integer "position", default: 0, null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capability_pack_id", "feature_id"], name: "idx_marlon_pack_features_unique", unique: true
  end

  create_table "marlon_capability_packs", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_marlon_capability_packs_on_key", unique: true
  end

  create_table "marlon_deliverables", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "pending", null: false
    t.date "due_date"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_marlon_deliverables_on_project_id"
    t.index ["status"], name: "index_marlon_deliverables_on_status"
  end

  create_table "marlon_features", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_marlon_features_on_key", unique: true
  end

  create_table "marlon_generated_artifacts", force: :cascade do |t|
    t.string "blueprint_key", null: false
    t.string "artifact_type", null: false
    t.string "path", null: false
    t.string "checksum"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blueprint_key", "path"], name: "idx_marlon_generated_artifacts_unique", unique: true
  end

  create_table "marlon_project_type_capability_packs", force: :cascade do |t|
    t.bigint "project_type_id", null: false
    t.bigint "capability_pack_id", null: false
    t.integer "position", default: 0, null: false
    t.json "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_type_id", "capability_pack_id"], name: "idx_marlon_project_type_packs_unique", unique: true
  end

  create_table "marlon_project_types", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_marlon_project_types_on_key", unique: true
  end

  create_table "marlon_projects", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.bigint "client_id"
    t.bigint "owner_id"
    t.bigint "purchase_id"
    t.string "status", default: "planning", null: false
    t.date "start_date"
    t.date "due_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_marlon_projects_on_client_id"
    t.index ["owner_id"], name: "index_marlon_projects_on_owner_id"
    t.index ["purchase_id"], name: "index_marlon_projects_on_purchase_id"
    t.index ["status"], name: "index_marlon_projects_on_status"
  end

  create_table "marlon_ticket_events", force: :cascade do |t|
    t.bigint "ticket_id", null: false
    t.bigint "actor_id"
    t.string "action", null: false
    t.text "detail"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_marlon_ticket_events_on_ticket_id"
  end

  create_table "marlon_tickets", force: :cascade do |t|
    t.string "number", null: false
    t.string "category", null: false
    t.string "title", null: false
    t.text "description"
    t.string "priority", default: "medium", null: false
    t.integer "urgency", default: 5, null: false
    t.string "status", default: "open", null: false
    t.bigint "submitted_by_id"
    t.string "organization_name"
    t.string "reseller_id"
    t.string "assigned_team"
    t.string "assigned_rep"
    t.jsonb "extra_fields"
    t.string "related_type"
    t.bigint "related_id"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_marlon_tickets_on_category"
    t.index ["number"], name: "index_marlon_tickets_on_number", unique: true
    t.index ["related_type", "related_id"], name: "index_marlon_tickets_on_related_type_and_related_id"
    t.index ["status"], name: "index_marlon_tickets_on_status"
    t.index ["submitted_by_id"], name: "index_marlon_tickets_on_submitted_by_id"
  end

  create_table "marlon_timesheets", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "user_id", null: false
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.date "worked_on", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_marlon_timesheets_on_project_id"
    t.index ["user_id"], name: "index_marlon_timesheets_on_user_id"
    t.index ["worked_on"], name: "index_marlon_timesheets_on_worked_on"
  end

  create_table "resellers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "storyline_arenas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "storyline_world_communities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "storyline_world_forges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "storylines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "supports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "role", default: "client", null: false
    t.string "phone"
    t.string "avatar_url"
    t.string "timezone", default: "Eastern Time (US & Canada)"
    t.string "locale", default: "en"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "dymond_bank_invoice_line_items", "dymond_bank_invoices", column: "invoice_id"
  add_foreign_key "dymond_bank_invoices", "dymond_bank_linked_accounts", column: "linked_account_id"
  add_foreign_key "dymond_bank_ledger_entries", "dymond_bank_accounts", column: "account_id"
  add_foreign_key "dymond_bank_payouts", "dymond_bank_accounts", column: "account_id"
  add_foreign_key "dymond_bank_payouts", "dymond_bank_linked_accounts", column: "linked_account_id"
  add_foreign_key "dymond_bank_royalty_payments", "dymond_bank_payouts", column: "payout_id"
  add_foreign_key "dymond_bank_royalty_payments", "dymond_bank_royalty_splits", column: "royalty_split_id"
  add_foreign_key "dymond_bank_royalty_payments", "dymond_bank_transactions", column: "source_transaction_id"
  add_foreign_key "dymond_bank_subscriptions", "dymond_bank_linked_accounts", column: "linked_account_id"
  add_foreign_key "dymond_bank_subscriptions", "dymond_bank_subscription_plans", column: "plan_id"
  add_foreign_key "dymond_bank_transactions", "dymond_bank_accounts", column: "account_id"
  add_foreign_key "dymond_bank_transactions", "dymond_bank_invoices", column: "invoice_id"
  add_foreign_key "dymond_dash_app_configs", "dymond_theme_themes", column: "theme_id"
  add_foreign_key "dymond_dash_installed_gems", "dymond_dash_ecosystem_gems", column: "ecosystem_gem_id"
  add_foreign_key "dymond_dash_nav_items", "dymond_dash_nav_sections", column: "section_id"
  add_foreign_key "dymond_dash_pending_gemfile_changes", "dymond_dash_ecosystem_gems", column: "ecosystem_gem_id"
  add_foreign_key "dymond_kb_articles", "dymond_kb_topics", column: "topic_id"
  add_foreign_key "dymond_site_footers", "dymond_site_sites", column: "site_id"
  add_foreign_key "dymond_site_nav_items", "dymond_site_nav_items", column: "parent_id"
  add_foreign_key "dymond_site_nav_items", "dymond_site_nav_menus", column: "nav_menu_id"
  add_foreign_key "dymond_site_nav_items", "dymond_site_pages", column: "page_id"
  add_foreign_key "dymond_site_nav_menus", "dymond_site_sites", column: "site_id"
  add_foreign_key "dymond_site_pages", "dymond_site_sites", column: "site_id"
  add_foreign_key "dymond_site_pages", "dymond_theme_themes", column: "theme_id"
  add_foreign_key "dymond_site_sections", "dymond_site_pages", column: "page_id"
  add_foreign_key "dymond_site_sections", "dymond_theme_themes", column: "theme_id"
  add_foreign_key "dymond_site_sites", "dymond_site_site_templates", column: "active_template_id"
  add_foreign_key "marlon_blueprint_concerns", "marlon_features", column: "feature_id"
  add_foreign_key "marlon_capability_pack_dependencies", "marlon_capability_packs", column: "capability_pack_id"
  add_foreign_key "marlon_capability_pack_dependencies", "marlon_capability_packs", column: "dependency_id"
  add_foreign_key "marlon_capability_pack_features", "marlon_capability_packs", column: "capability_pack_id"
  add_foreign_key "marlon_capability_pack_features", "marlon_features", column: "feature_id"
  add_foreign_key "marlon_deliverables", "marlon_projects", column: "project_id"
  add_foreign_key "marlon_project_type_capability_packs", "marlon_capability_packs", column: "capability_pack_id"
  add_foreign_key "marlon_project_type_capability_packs", "marlon_project_types", column: "project_type_id"
  add_foreign_key "marlon_ticket_events", "marlon_tickets", column: "ticket_id"
  add_foreign_key "marlon_timesheets", "marlon_projects", column: "project_id"
  add_foreign_key "sessions", "users"
end
