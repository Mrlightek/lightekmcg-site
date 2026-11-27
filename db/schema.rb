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

ActiveRecord::Schema[8.0].define(version: 2026_11_27_184000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "account_setup_settings", force: :cascade do |t|
    t.integer "link_minutes", default: 2880, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
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

  create_table "agency_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "brand_name", null: false
    t.string "logo_url"
    t.string "support_email"
    t.string "accent_color", default: "#d4af37", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_agency_profiles_on_user_id", unique: true
  end

  create_table "architectures", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "artifacts", force: :cascade do |t|
    t.bigint "creation_job_id"
    t.string "kind", null: false
    t.string "filename", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "studio_operation_id"
    t.index ["creation_job_id"], name: "index_artifacts_on_creation_job_id"
    t.index ["studio_operation_id"], name: "index_artifacts_on_studio_operation_id"
  end

  create_table "catalogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "channels", force: :cascade do |t|
    t.string "name"
    t.string "logo"
    t.bigint "show_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["show_id"], name: "index_channels_on_show_id"
  end

  create_table "communities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "owner_profile_id"
    t.bigint "site_id"
    t.string "request_key"
    t.string "name"
    t.string "slug"
    t.text "description"
    t.string "visibility", default: "public", null: false
    t.jsonb "sections", default: ["featured", "live", "conversations", "clips", "events", "members", "playlists", "about"], null: false
    t.string "audience", default: "everyone", null: false
    t.string "moderation_state", default: "active", null: false
    t.index ["owner_profile_id", "request_key"], name: "idx_community_request_unique", unique: true
    t.index ["owner_profile_id"], name: "index_communities_on_owner_profile_id"
    t.index ["site_id", "moderation_state"], name: "index_communities_on_site_id_and_moderation_state"
    t.index ["site_id"], name: "index_communities_on_site_id"
    t.index ["slug"], name: "index_communities_on_slug", unique: true
  end

  create_table "compute_policies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "purpose", null: false
    t.bigint "preferred_provider_id"
    t.bigint "fallback_provider_id"
    t.integer "monthly_cost_ceiling_cents"
    t.integer "automatic_approval_ceiling_cents"
    t.jsonb "allowed_regions", default: [], null: false
    t.jsonb "required_capabilities", default: [], null: false
    t.jsonb "rules", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fallback_provider_id"], name: "index_compute_policies_on_fallback_provider_id"
    t.index ["preferred_provider_id"], name: "index_compute_policies_on_preferred_provider_id"
    t.index ["slug"], name: "index_compute_policies_on_slug", unique: true
  end

  create_table "compute_providers", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "adapter_type", default: "declarative", null: false
    t.string "adapter_class"
    t.string "api_base_url"
    t.string "documentation_url"
    t.string "openapi_url"
    t.string "credential_secret_slug"
    t.string "status", default: "draft", null: false
    t.string "health_status", default: "unknown", null: false
    t.datetime "last_healthcheck_at"
    t.jsonb "capabilities", default: {}, null: false
    t.jsonb "configuration", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_compute_providers_on_capabilities", using: :gin
    t.index ["configuration"], name: "index_compute_providers_on_configuration", using: :gin
    t.index ["health_status"], name: "index_compute_providers_on_health_status"
    t.index ["slug"], name: "index_compute_providers_on_slug", unique: true
    t.index ["status"], name: "index_compute_providers_on_status"
  end

  create_table "creation_jobs", force: :cascade do |t|
    t.bigint "studio_scene_id", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "manifest", default: {}, null: false
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_creation_jobs_on_status"
    t.index ["studio_scene_id"], name: "index_creation_jobs_on_studio_scene_id"
  end

  create_table "dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "database_requests", force: :cascade do |t|
    t.string "requestable_type", null: false
    t.bigint "requestable_id", null: false
    t.jsonb "payload"
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requestable_type", "requestable_id"], name: "index_database_requests_on_requestable"
  end

  create_table "departments", force: :cascade do |t|
    t.string "title"
    t.bigint "system_job_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["system_job_id"], name: "index_departments_on_system_job_id"
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
    t.bigint "principal_cents", default: 0, null: false
    t.bigint "processor_recovery_cents", default: 0, null: false
    t.bigint "network_fee_cents", default: 0, null: false
    t.string "payable_type"
    t.bigint "payable_id"
    t.string "payment_context"
    t.index ["account_id"], name: "index_dymond_bank_transactions_on_account_id"
    t.index ["idempotency_key"], name: "index_dymond_bank_transactions_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["invoice_id"], name: "index_dymond_bank_transactions_on_invoice_id"
    t.index ["payable_type", "payable_id"], name: "index_dymond_bank_transactions_on_payable"
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

  create_table "dymond_booking_bookings", force: :cascade do |t|
    t.bigint "resource_id", null: false
    t.bigint "requested_by_id", null: false
    t.datetime "start_time", null: false
    t.datetime "end_time", null: false
    t.string "status", default: "pending", null: false
    t.text "notes"
    t.bigint "total_cents", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id"], name: "index_dymond_booking_bookings_on_resource_id"
    t.index ["start_time"], name: "index_dymond_booking_bookings_on_start_time"
    t.index ["status"], name: "index_dymond_booking_bookings_on_status"
  end

  create_table "dymond_booking_event_rsvps", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "attendee_id", null: false
    t.string "status", default: "going", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "attendee_id"], name: "index_dymond_booking_event_rsvps_on_event_id_and_attendee_id", unique: true
    t.index ["event_id"], name: "index_dymond_booking_event_rsvps_on_event_id"
  end

  create_table "dymond_booking_events", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.string "location"
    t.datetime "start_time", null: false
    t.datetime "end_time"
    t.bigint "organizer_id"
    t.integer "capacity"
    t.boolean "public", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public"], name: "index_dymond_booking_events_on_public"
    t.index ["start_time"], name: "index_dymond_booking_events_on_start_time"
  end

  create_table "dymond_booking_resources", force: :cascade do |t|
    t.string "name", null: false
    t.string "resource_type", default: "service", null: false
    t.bigint "owner_id"
    t.text "description"
    t.bigint "rate_cents", default: 0
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_type"], name: "index_dymond_booking_resources_on_resource_type"
  end

  create_table "dymond_catalog_marketplace_listings", force: :cascade do |t|
    t.bigint "offer_id", null: false
    t.string "title", null: false
    t.text "summary"
    t.string "category", null: false
    t.boolean "published", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "configuration", default: {}, null: false
    t.string "marketing_headline", limit: 180
    t.text "marketing_subheadline"
    t.string "best_for", limit: 160
    t.string "plan_badge", limit: 50
    t.string "cta_label", limit: 60
    t.text "fulfillment_summary"
    t.jsonb "marketing_features", default: [], null: false
    t.jsonb "marketing_faq", default: [], null: false
    t.index ["offer_id"], name: "index_dymond_catalog_marketplace_listings_on_offer_id", unique: true
    t.index ["published", "category", "position"], name: "idx_marketplace_merchandising"
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

  create_table "dymond_dash_system_logs", force: :cascade do |t|
    t.string "environment", null: false
    t.string "node_instance"
    t.string "source", null: false
    t.string "service", null: false
    t.string "severity", null: false
    t.string "event_type", null: false
    t.text "message", null: false
    t.string "correlation_id"
    t.bigint "tenant_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "timestamp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["correlation_id"], name: "index_dymond_dash_system_logs_on_correlation_id"
    t.index ["environment"], name: "index_dymond_dash_system_logs_on_environment"
    t.index ["event_type"], name: "index_dymond_dash_system_logs_on_event_type"
    t.index ["metadata"], name: "index_dymond_dash_system_logs_on_metadata", using: :gin
    t.index ["node_instance"], name: "index_dymond_dash_system_logs_on_node_instance"
    t.index ["service"], name: "index_dymond_dash_system_logs_on_service"
    t.index ["severity", "timestamp"], name: "index_dymond_dash_system_logs_on_severity_and_timestamp"
    t.index ["severity"], name: "index_dymond_dash_system_logs_on_severity"
    t.index ["source", "timestamp"], name: "index_dymond_dash_system_logs_on_source_and_timestamp"
    t.index ["source"], name: "index_dymond_dash_system_logs_on_source"
    t.index ["tenant_id"], name: "index_dymond_dash_system_logs_on_tenant_id"
    t.index ["timestamp"], name: "index_dymond_dash_system_logs_on_timestamp"
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
    t.string "correlation_id"
    t.index ["correlation_id"], name: "index_dymond_dispatch_work_items_on_correlation_id"
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
    t.jsonb "metadata", default: {}, null: false
    t.index ["article_id"], name: "index_dymond_kb_articles_on_article_id", unique: true
    t.index ["featured"], name: "index_dymond_kb_articles_on_featured"
    t.index ["metadata"], name: "index_dymond_kb_articles_on_metadata", using: :gin
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

  create_table "dymond_studio_blender_scenes", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "asset_id", null: false
    t.string "status", default: "uploaded", null: false
    t.bigint "output_asset_id"
    t.text "render_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_dymond_studio_blender_scenes_on_status"
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

  create_table "dymond_studio_scripts", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "project_id"
    t.bigint "owner_id"
    t.string "format", default: "screenplay", null: false
    t.string "status", default: "draft", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_dymond_studio_scripts_on_project_id"
    t.index ["status"], name: "index_dymond_studio_scripts_on_status"
  end

  create_table "dymond_studio_storyboard_panels", force: :cascade do |t|
    t.bigint "storyboard_id", null: false
    t.integer "panel_number", default: 1, null: false
    t.text "description"
    t.string "shot_type", default: "medium"
    t.integer "duration_seconds", default: 5
    t.bigint "media_asset_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["storyboard_id", "panel_number"], name: "idx_on_storyboard_id_panel_number_25bf91628c", unique: true
    t.index ["storyboard_id"], name: "index_dymond_studio_storyboard_panels_on_storyboard_id"
  end

  create_table "dymond_studio_storyboards", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "script_id"
    t.bigint "project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_dymond_studio_storyboards_on_project_id"
    t.index ["script_id"], name: "index_dymond_studio_storyboards_on_script_id"
  end

  create_table "dymond_studio_text_overlays", force: :cascade do |t|
    t.bigint "timeline_id", null: false
    t.string "content", null: false
    t.float "start_time", default: 0.0, null: false
    t.float "end_time", null: false
    t.string "position", default: "bottom"
    t.integer "font_size", default: 36
    t.string "color", default: "white"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["timeline_id"], name: "index_dymond_studio_text_overlays_on_timeline_id"
  end

  create_table "dymond_studio_timeline_clips", force: :cascade do |t|
    t.bigint "track_id", null: false
    t.bigint "media_asset_id", null: false
    t.float "timeline_start", default: 0.0, null: false
    t.float "source_in", default: 0.0, null: false
    t.float "source_out", null: false
    t.string "transition_in", default: "cut"
    t.string "transition_out", default: "cut"
    t.float "transition_duration", default: 0.5
    t.string "filter"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["track_id", "position"], name: "index_dymond_studio_timeline_clips_on_track_id_and_position"
    t.index ["track_id"], name: "index_dymond_studio_timeline_clips_on_track_id"
  end

  create_table "dymond_studio_timeline_tracks", force: :cascade do |t|
    t.bigint "timeline_id", null: false
    t.string "track_type", default: "video", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["timeline_id", "position"], name: "idx_on_timeline_id_position_58099e9345"
    t.index ["timeline_id"], name: "index_dymond_studio_timeline_tracks_on_timeline_id"
  end

  create_table "dymond_studio_timelines", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "storyboard_id"
    t.bigint "project_id"
    t.string "status", default: "draft", null: false
    t.bigint "output_asset_id"
    t.text "render_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_dymond_studio_timelines_on_status"
    t.index ["storyboard_id"], name: "index_dymond_studio_timelines_on_storyboard_id"
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

  create_table "episodes", force: :cascade do |t|
    t.string "title"
    t.string "subtitle"
    t.string "url"
    t.text "description"
    t.string "show_title"
    t.text "show_description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "season"
  end

  create_table "gatekeeper_application_launches", force: :cascade do |t|
    t.bigint "gatekeeper_application_template_id", null: false
    t.bigint "gatekeeper_node_id"
    t.bigint "provisioning_request_id"
    t.bigint "owner_id", null: false
    t.bigint "requested_by_id", null: false
    t.string "name", null: false
    t.string "domain", null: false
    t.string "status", default: "queued", null: false
    t.text "error_message"
    t.jsonb "receipt", default: {}, null: false
    t.jsonb "template_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_gatekeeper_application_launches_on_domain", unique: true
    t.index ["gatekeeper_application_template_id"], name: "idx_on_gatekeeper_application_template_id_36eccce17b"
    t.index ["gatekeeper_node_id"], name: "index_gatekeeper_application_launches_on_gatekeeper_node_id"
    t.index ["owner_id"], name: "index_gatekeeper_application_launches_on_owner_id"
    t.index ["provisioning_request_id"], name: "idx_on_provisioning_request_id_73793da448"
    t.index ["requested_by_id"], name: "index_gatekeeper_application_launches_on_requested_by_id"
    t.index ["status", "updated_at"], name: "index_gatekeeper_application_launches_on_status_and_updated_at"
  end

  create_table "gatekeeper_application_templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "preview_domain"
    t.string "kind", default: "native_rails", null: false
    t.string "image"
    t.string "build_status", default: "ready", null: false
    t.string "source_ref"
    t.integer "container_port", default: 3000, null: false
    t.string "credential_slug"
    t.boolean "rails_database", default: true, null: false
    t.boolean "rails_worker", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "build_identity", default: {}, null: false
    t.boolean "lightek_application", default: false, null: false
  end

  create_table "gatekeeper_hosted_applications", force: :cascade do |t|
    t.bigint "gatekeeper_node_id", null: false
    t.bigint "gatekeeper_project_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "requested_by_id", null: false
    t.bigint "gatekeeper_operation_id"
    t.string "name", null: false
    t.string "domain", null: false
    t.string "public_key", null: false
    t.string "status", default: "queued", null: false
    t.integer "remote_site_id"
    t.text "error_message"
    t.jsonb "receipt", default: {}, null: false
    t.datetime "started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_gatekeeper_hosted_applications_on_domain", unique: true
    t.index ["gatekeeper_node_id"], name: "index_gatekeeper_hosted_applications_on_gatekeeper_node_id"
    t.index ["gatekeeper_operation_id"], name: "idx_on_gatekeeper_operation_id_31e90c3546"
    t.index ["gatekeeper_project_id"], name: "index_gatekeeper_hosted_applications_on_gatekeeper_project_id"
    t.index ["owner_id", "status"], name: "index_gatekeeper_hosted_applications_on_owner_id_and_status"
    t.index ["owner_id"], name: "index_gatekeeper_hosted_applications_on_owner_id"
    t.index ["public_key"], name: "index_gatekeeper_hosted_applications_on_public_key", unique: true
    t.index ["requested_by_id"], name: "index_gatekeeper_hosted_applications_on_requested_by_id"
  end

  create_table "gatekeeper_installations", force: :cascade do |t|
    t.bigint "gatekeeper_node_id", null: false
    t.string "domain", null: false
    t.string "channel", default: "stable", null: false
    t.boolean "automatic_updates", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.string "current_version"
    t.string "current_image"
    t.datetime "last_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "adapter", default: "native_rails", null: false
    t.string "component", default: "lightek_app", null: false
    t.string "repository", default: "https://github.com/Mrlightek/lightekmcg-site.git", null: false
    t.jsonb "deployment_config", default: {}, null: false
    t.bigint "account_id"
    t.bigint "pinned_release_id"
    t.bigint "gatekeeper_project_id"
    t.index ["account_id"], name: "index_gatekeeper_installations_on_account_id"
    t.index ["gatekeeper_node_id", "domain", "component"], name: "index_fleet_installation_component", unique: true
    t.index ["gatekeeper_node_id"], name: "index_gatekeeper_installations_on_gatekeeper_node_id"
    t.index ["gatekeeper_project_id"], name: "index_gatekeeper_installations_on_gatekeeper_project_id"
    t.index ["pinned_release_id"], name: "index_gatekeeper_installations_on_pinned_release_id"
  end

  create_table "gatekeeper_nodes", force: :cascade do |t|
    t.string "name", null: false
    t.string "hostname"
    t.string "ip_address", null: false
    t.string "ssh_user", default: "root", null: false
    t.integer "ssh_port", default: 22, null: false
    t.string "ssh_key_path"
    t.string "provider"
    t.string "provider_id"
    t.string "region"
    t.string "status", default: "unknown", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_healthcheck_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "compute_provider_id"
    t.bigint "provisioning_profile_id"
    t.bigint "compute_policy_id"
    t.string "provider_resource_id"
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "purpose"
    t.string "plan"
    t.string "image"
    t.string "public_ipv6"
    t.string "private_ip"
    t.integer "estimated_monthly_cost_cents"
    t.index ["compute_policy_id"], name: "index_gatekeeper_nodes_on_compute_policy_id"
    t.index ["compute_provider_id"], name: "index_gatekeeper_nodes_on_compute_provider_id"
    t.index ["name"], name: "index_gatekeeper_nodes_on_name", unique: true
    t.index ["owner_type", "owner_id"], name: "index_gatekeeper_nodes_on_owner_type_and_owner_id"
    t.index ["provider_resource_id"], name: "index_gatekeeper_nodes_on_provider_resource_id"
    t.index ["provisioning_profile_id"], name: "index_gatekeeper_nodes_on_provisioning_profile_id"
    t.index ["status"], name: "index_gatekeeper_nodes_on_status"
  end

  create_table "gatekeeper_operations", force: :cascade do |t|
    t.bigint "gatekeeper_node_id", null: false
    t.bigint "gatekeeper_project_id"
    t.string "capability", null: false
    t.string "requested_by", null: false
    t.string "status", default: "queued", null: false
    t.text "command"
    t.text "output"
    t.integer "exit_status"
    t.jsonb "parameters", default: {}, null: false
    t.jsonb "result", default: {}, null: false
    t.string "error_class"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capability"], name: "index_gatekeeper_operations_on_capability"
    t.index ["created_at"], name: "index_gatekeeper_operations_on_created_at"
    t.index ["gatekeeper_node_id"], name: "index_gatekeeper_operations_on_gatekeeper_node_id"
    t.index ["gatekeeper_project_id"], name: "index_gatekeeper_operations_on_gatekeeper_project_id"
    t.index ["status"], name: "index_gatekeeper_operations_on_status"
  end

  create_table "gatekeeper_projects", force: :cascade do |t|
    t.bigint "gatekeeper_node_id", null: false
    t.string "name", null: false
    t.string "repository", null: false
    t.string "branch", default: "main", null: false
    t.string "domain", null: false
    t.string "app_root", null: false
    t.string "app_user", default: "lightek", null: false
    t.string "ruby_version", default: "3.3.6", null: false
    t.string "rails_env", default: "production", null: false
    t.string "apache_service_name", default: "apache2", null: false
    t.string "sidekiq_service_name"
    t.string "status", default: "unknown", null: false
    t.string "deployed_sha"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_deployed_at"
    t.datetime "last_healthcheck_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_gatekeeper_projects_on_domain", unique: true
    t.index ["gatekeeper_node_id"], name: "index_gatekeeper_projects_on_gatekeeper_node_id"
    t.index ["name"], name: "index_gatekeeper_projects_on_name", unique: true
    t.index ["status"], name: "index_gatekeeper_projects_on_status"
  end

  create_table "gatekeeper_releases", force: :cascade do |t|
    t.string "version", null: false
    t.string "source_sha", null: false
    t.string "image"
    t.string "channel", default: "stable", null: false
    t.text "notes"
    t.boolean "backward_compatible", default: false, null: false
    t.string "created_by", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "adapter", default: "native_rails", null: false
    t.string "component", default: "lightek_app", null: false
    t.string "repository", default: "https://github.com/Mrlightek/lightekmcg-site.git", null: false
    t.index ["version"], name: "index_gatekeeper_releases_on_version", unique: true
  end

  create_table "gatekeeper_rollouts", force: :cascade do |t|
    t.bigint "gatekeeper_release_id", null: false
    t.string "status", default: "draft", null: false
    t.string "requested_by", null: false
    t.integer "canary_size", default: 1, null: false
    t.integer "batch_size", default: 10, null: false
    t.boolean "auto_promote", default: false, null: false
    t.boolean "promoted", default: false, null: false
    t.datetime "scheduled_at"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gatekeeper_release_id"], name: "index_gatekeeper_rollouts_on_gatekeeper_release_id"
    t.index ["status"], name: "index_gatekeeper_rollouts_on_status"
  end

  create_table "gatekeeper_update_targets", force: :cascade do |t|
    t.bigint "gatekeeper_rollout_id", null: false
    t.bigint "gatekeeper_installation_id", null: false
    t.bigint "gatekeeper_operation_id"
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.boolean "canary", default: false, null: false
    t.string "previous_version"
    t.string "previous_image"
    t.jsonb "receipt", default: {}, null: false
    t.string "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gatekeeper_installation_id"], name: "index_fleet_active_installation", unique: true, where: "((status)::text = ANY ((ARRAY['reserved'::character varying, 'queued'::character varying, 'running'::character varying, 'failed'::character varying])::text[]))"
    t.index ["gatekeeper_installation_id"], name: "index_gatekeeper_update_targets_on_gatekeeper_installation_id"
    t.index ["gatekeeper_operation_id"], name: "index_gatekeeper_update_targets_on_gatekeeper_operation_id"
    t.index ["gatekeeper_rollout_id", "gatekeeper_installation_id"], name: "index_fleet_target_once", unique: true
    t.index ["gatekeeper_rollout_id", "status"], name: "index_fleet_target_status"
    t.index ["gatekeeper_rollout_id"], name: "index_gatekeeper_update_targets_on_gatekeeper_rollout_id"
  end

  create_table "homes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "hosting_packages", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "compute_provider_id", null: false
    t.bigint "gatekeeper_application_template_id", null: false
    t.string "region", null: false
    t.string "provider_plan", null: false
    t.integer "monthly_cost_ceiling_cents", null: false
    t.integer "minimum_margin_cents", default: 1, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "wholesale_price_cents"
    t.integer "reseller_minimum_margin_cents", default: 500, null: false
    t.index ["compute_provider_id"], name: "index_hosting_packages_on_compute_provider_id"
    t.index ["gatekeeper_application_template_id"], name: "idx_hosting_package_template"
    t.index ["product_id"], name: "index_hosting_packages_on_product_id", unique: true
    t.check_constraint "reseller_minimum_margin_cents >= 0", name: "hosting_reseller_margin_nonnegative"
    t.check_constraint "wholesale_price_cents IS NULL OR wholesale_price_cents > 0", name: "hosting_wholesale_positive"
  end

  create_table "job_items", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "lightek_accounting_audit_events", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "actor_id", null: false
    t.string "action", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.string "proof_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_accounting_audit_events_on_actor_id"
    t.index ["book_id"], name: "index_lightek_accounting_audit_events_on_book_id"
  end

  create_table "lightek_accounting_automations", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "actor_id", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "next_run_at", null: false
    t.datetime "last_run_at"
    t.string "error_code"
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_accounting_automations_on_actor_id"
    t.index ["book_id"], name: "index_lightek_accounting_automations_on_book_id"
  end

  create_table "lightek_accounting_bank_accounts", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.string "name", null: false
    t.date "opening_on", null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_lightek_accounting_bank_accounts_on_book_id"
  end

  create_table "lightek_accounting_books", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", null: false
    t.string "currency", default: "USD", null: false
    t.string "timezone", default: "America/New_York", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_accounting_books_on_employer_id"
  end

  create_table "lightek_accounting_categories", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "schedule_code"
    t.integer "deduction_bps", default: 10000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_lightek_accounting_categories_on_book_id"
  end

  create_table "lightek_accounting_imports", force: :cascade do |t|
    t.bigint "bank_account_id", null: false
    t.bigint "book_id", null: false
    t.bigint "actor_id", null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.string "status", default: "preview", null: false
    t.string "source_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_accounting_imports_on_actor_id"
    t.index ["bank_account_id"], name: "index_lightek_accounting_imports_on_bank_account_id"
    t.index ["book_id"], name: "index_lightek_accounting_imports_on_book_id"
  end

  create_table "lightek_accounting_reconciliations", force: :cascade do |t|
    t.bigint "bank_account_id", null: false
    t.bigint "book_id", null: false
    t.bigint "actor_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.string "status", default: "draft", null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_accounting_reconciliations_on_actor_id"
    t.index ["bank_account_id", "starts_on", "ends_on"], name: "idx_accounting_final_period", unique: true, where: "((status)::text = 'final'::text)"
    t.index ["bank_account_id"], name: "index_lightek_accounting_reconciliations_on_bank_account_id"
    t.index ["book_id"], name: "index_lightek_accounting_reconciliations_on_book_id"
  end

  create_table "lightek_accounting_rules", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "category_id", null: false
    t.integer "priority", default: 100, null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_lightek_accounting_rules_on_book_id"
    t.index ["category_id"], name: "index_lightek_accounting_rules_on_category_id"
  end

  create_table "lightek_accounting_transactions", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "bank_account_id", null: false
    t.bigint "category_id"
    t.bigint "statement_import_id"
    t.bigint "reconciliation_id"
    t.date "posted_on", null: false
    t.string "source_key", null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bank_account_id", "posted_on"], name: "idx_accounting_account_date"
    t.index ["bank_account_id", "reconciliation_id"], name: "idx_accounting_uncleared"
    t.index ["bank_account_id", "source_key"], name: "idx_accounting_source_key", unique: true
    t.index ["bank_account_id"], name: "index_lightek_accounting_transactions_on_bank_account_id"
    t.index ["book_id", "posted_on", "id"], name: "idx_accounting_book_date"
    t.index ["book_id"], name: "index_lightek_accounting_transactions_on_book_id"
    t.index ["category_id"], name: "index_lightek_accounting_transactions_on_category_id"
    t.index ["reconciliation_id"], name: "index_lightek_accounting_transactions_on_reconciliation_id"
    t.index ["statement_import_id"], name: "index_lightek_accounting_transactions_on_statement_import_id"
  end

  create_table "lightek_accounting_workbooks", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "actor_id", null: false
    t.string "name", null: false
    t.string "record_key", null: false
    t.jsonb "sealed_data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_accounting_workbooks_on_actor_id"
    t.index ["book_id"], name: "index_lightek_accounting_workbooks_on_book_id"
  end

  create_table "lightek_agency_demo_requests", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.string "email_address", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "nonce", null: false
    t.string "status", default: "pending", null: false
    t.datetime "invitation_queued_at"
    t.datetime "verified_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "growth_visit_id"
    t.index ["agency_id", "email_address", "created_at"], name: "index_demo_requests_on_agency_email_created"
    t.index ["agency_id"], name: "index_lightek_agency_demo_requests_on_agency_id"
    t.index ["growth_visit_id"], name: "index_lightek_agency_demo_requests_on_growth_visit_id"
  end

  create_table "lightek_agency_demo_settings", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.bigint "public_site_id"
    t.bigint "upgrade_product_id"
    t.boolean "public_enabled", default: false, null: false
    t.integer "duration_days", default: 14, null: false
    t.integer "max_active", default: 20, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_lightek_agency_demo_settings_on_agency_id", unique: true
  end

  create_table "lightek_agency_demos", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.bigint "client_id"
    t.bigint "site_id"
    t.bigint "demo_request_id"
    t.bigint "upgrade_order_id"
    t.string "public_id", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.boolean "created_client", default: false, null: false
    t.datetime "expires_at", null: false
    t.datetime "converted_at"
    t.datetime "cleaned_at"
    t.string "cleanup_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agency_id"], name: "index_lightek_agency_demos_on_agency_id"
    t.index ["client_id"], name: "index_lightek_agency_demos_on_client_id"
    t.index ["demo_request_id"], name: "index_lightek_agency_demos_on_demo_request_id", unique: true, where: "(demo_request_id IS NOT NULL)"
    t.index ["public_id"], name: "index_lightek_agency_demos_on_public_id", unique: true
    t.index ["site_id"], name: "index_lightek_agency_demos_on_site_id", unique: true, where: "(site_id IS NOT NULL)"
    t.index ["status", "expires_at"], name: "index_lightek_agency_demos_on_status_and_expires_at"
  end

  create_table "lightek_agency_installed_packages", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "source_key", null: false
    t.boolean "runtime", default: false, null: false
    t.jsonb "policy", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_lightek_agency_installed_packages_on_user_id", unique: true
  end

  create_table "lightek_agency_package_storage", force: :cascade do |t|
    t.bigint "installed_package_id", null: false
    t.bigint "blob_id", null: false
    t.bigint "bytes", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["installed_package_id", "blob_id"], name: "index_package_storage_on_account_blob", unique: true
    t.index ["installed_package_id"], name: "index_lightek_agency_package_storage_on_installed_package_id"
  end

  create_table "lightek_agency_package_usages", force: :cascade do |t|
    t.bigint "installed_package_id", null: false
    t.string "feature", null: false
    t.date "period", null: false
    t.bigint "used", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["installed_package_id", "feature", "period"], name: "index_package_usage_on_account_feature_period", unique: true
    t.index ["installed_package_id"], name: "index_lightek_agency_package_usages_on_installed_package_id"
  end

  create_table "lightek_agency_site_memberships", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.string "role", default: "marketer", null: false
    t.bigint "granted_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_id"], name: "index_lightek_agency_site_memberships_on_granted_by_id"
    t.index ["site_id", "user_id"], name: "idx_agency_site_member", unique: true
    t.index ["site_id"], name: "index_lightek_agency_site_memberships_on_site_id"
    t.index ["user_id"], name: "index_lightek_agency_site_memberships_on_user_id"
  end

  create_table "lightek_agency_trial_requests", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "operator_id", null: false
    t.string "email_address", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "business_type", default: "general", null: false
    t.index ["operator_id"], name: "index_lightek_agency_trial_requests_on_operator_id"
    t.index ["site_id", "email_address", "created_at"], name: "index_agency_trial_requests_on_site_and_email"
    t.index ["site_id"], name: "index_lightek_agency_trial_requests_on_site_id"
  end

  create_table "lightek_agency_trials", force: :cascade do |t|
    t.bigint "prospect_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "billing_site_id", null: false
    t.bigint "order_id"
    t.bigint "paid_order_id"
    t.string "brand_name", null: false
    t.string "sample_client_name", default: "Oak Street Books", null: false
    t.integer "sample_retail_dollars", default: 49, null: false
    t.datetime "expires_at", null: false
    t.datetime "activated_at"
    t.datetime "paid_through"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "business_type", default: "general", null: false
    t.index ["billing_site_id"], name: "index_lightek_agency_trials_on_billing_site_id"
    t.index ["operator_id"], name: "index_lightek_agency_trials_on_operator_id"
    t.index ["order_id"], name: "index_lightek_agency_trials_on_order_id", unique: true
    t.index ["paid_order_id"], name: "index_lightek_agency_trials_on_paid_order_id"
    t.index ["prospect_id"], name: "index_lightek_agency_trials_on_prospect_id", unique: true
  end

  create_table "lightek_audience_leases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "key", null: false
    t.string "source", null: false
    t.datetime "expires_at", null: false
    t.index ["expires_at"], name: "index_lightek_audience_leases_on_expires_at"
    t.index ["key"], name: "index_lightek_audience_leases_on_key", unique: true
    t.index ["user_id"], name: "index_lightek_audience_leases_on_user_id"
  end

  create_table "lightek_blog_editorial_schedules", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "actor_id", null: false
    t.bigint "last_goal_id"
    t.string "delegation_id", null: false
    t.string "revision", null: false
    t.string "cadence", null: false
    t.string "article_status", null: false
    t.boolean "enabled", default: false, null: false
    t.boolean "social_draft", default: false, null: false
    t.json "topics", null: false
    t.json "sources", null: false
    t.datetime "next_run_at"
    t.string "last_error", limit: 500
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled", "next_run_at"], name: "idx_on_enabled_next_run_at_54f53422f6"
    t.index ["site_id"], name: "index_lightek_blog_editorial_schedules_on_site_id", unique: true
  end

  create_table "lightek_blog_entries", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "post_id", null: false
    t.string "slug", limit: 160, null: false
    t.string "status", default: "draft", null: false
    t.text "excerpt"
    t.string "category", limit: 80
    t.datetime "published_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_lightek_blog_entries_on_post_id", unique: true
    t.index ["site_id", "slug"], name: "index_lightek_blog_entries_on_site_id_and_slug", unique: true
    t.index ["site_id", "status", "published_at"], name: "idx_blog_publication_feed"
    t.index ["site_id"], name: "index_lightek_blog_entries_on_site_id"
    t.check_constraint "(status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying, 'archived'::character varying]::text[])) AND (status::text <> 'published'::text OR published_at IS NOT NULL)", name: "blog_publication_state_valid"
  end

  create_table "lightek_commerce_billing_invoices", force: :cascade do |t|
    t.bigint "subscription_id", null: false
    t.string "processor_reference", null: false
    t.bigint "settlement_order_id"
    t.integer "amount_paid_cents", null: false
    t.string "currency", null: false
    t.datetime "paid_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["processor_reference"], name: "index_lightek_commerce_billing_invoices_on_processor_reference", unique: true
    t.index ["settlement_order_id"], name: "idx_billing_invoice_settlement", unique: true
    t.index ["subscription_id"], name: "idx_billing_invoice_subscription"
  end

  create_table "lightek_commerce_collections", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.boolean "published", default: false, null: false
    t.string "source", default: "manual", null: false
    t.string "matching", default: "all", null: false
    t.json "product_ids", default: [], null: false
    t.json "conditions", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "slug"], name: "idx_commerce_collections_site_slug", unique: true
  end

  create_table "lightek_commerce_customer_segments", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "minimum_orders"
    t.integer "maximum_orders"
    t.bigint "minimum_net_spend_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "slug"], name: "idx_commerce_customer_segments_site_slug", unique: true
  end

  create_table "lightek_commerce_discount_uses", force: :cascade do |t|
    t.bigint "discount_id", null: false
    t.bigint "order_id", null: false
    t.bigint "buyer_id"
    t.integer "amount_cents", null: false
    t.index ["discount_id", "buyer_id"], name: "idx_commerce_discount_uses_rule_buyer"
    t.index ["order_id", "discount_id"], name: "idx_commerce_discount_uses_order_rule", unique: true
    t.index ["order_id"], name: "index_lightek_commerce_discount_uses_on_order_id"
  end

  create_table "lightek_commerce_discounts", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "code"
    t.string "kind", null: false
    t.integer "amount", null: false
    t.integer "minimum_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "combinable", default: false, null: false
    t.bigint "target_collection_id"
    t.bigint "target_product_id"
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.integer "usage_limit"
    t.integer "buyer_limit"
    t.bigint "qualifying_product_id"
    t.bigint "qualifying_collection_id"
    t.integer "buy_quantity"
    t.integer "get_quantity"
    t.integer "applications_per_order"
    t.string "reward_type"
    t.bigint "customer_segment_id"
    t.index ["customer_segment_id"], name: "idx_commerce_discounts_segment"
    t.index ["site_id", "code"], name: "index_lightek_commerce_discounts_on_site_id_and_code", unique: true
    t.index ["site_id"], name: "index_lightek_commerce_discounts_on_site_id"
  end

  create_table "lightek_commerce_dispute_cases", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "processor_reference", null: false
    t.string "status", null: false
    t.string "reason", null: false
    t.integer "amount_cents", null: false
    t.datetime "due_at"
    t.datetime "alerted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_lightek_commerce_dispute_cases_on_order_id"
    t.index ["processor_reference"], name: "index_lightek_commerce_dispute_cases_on_processor_reference", unique: true
  end

  create_table "lightek_commerce_gift_cards", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "purchase_order_id", null: false
    t.string "store_scope", null: false
    t.boolean "livemode", null: false
    t.string "code_digest", null: false
    t.text "encrypted_code", null: false
    t.integer "face_cents", null: false
    t.integer "available_cents", null: false
    t.datetime "blocked_at"
    t.datetime "disputed_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["store_scope", "livemode"], name: "idx_commerce_gift_cards_scope_mode"
    t.index ["code_digest"], name: "index_lightek_commerce_gift_cards_on_code_digest", unique: true
    t.index ["purchase_order_id"], name: "index_lightek_commerce_gift_cards_on_purchase_order_id", unique: true
    t.index ["site_id"], name: "index_lightek_commerce_gift_cards_on_site_id"
    t.check_constraint "available_cents >= 0 AND available_cents <= face_cents AND face_cents > 0", name: "commerce_gift_card_balance"
  end

  create_table "lightek_commerce_gift_redemptions", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "gift_card_id", null: false
    t.integer "amount_cents", null: false
    t.integer "cash_cents", null: false
    t.string "state", default: "held", null: false
    t.string "tax_calculation", null: false
    t.string "tax_transaction"
    t.string "tax_reversal"
    t.datetime "payment_attempted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gift_card_id"], name: "index_lightek_commerce_gift_redemptions_on_gift_card_id"
    t.index ["order_id"], name: "index_lightek_commerce_gift_redemptions_on_order_id", unique: true
    t.check_constraint "amount_cents > 0 AND cash_cents >= 0", name: "commerce_gift_redemption_amount"
    t.check_constraint "state IN ('held', 'captured', 'released', 'refunded')", name: "commerce_gift_redemption_state"
  end

  create_table "lightek_commerce_network_accounts", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "user_id", null: false
    t.bigint "site_id", null: false
    t.string "source_subject", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["peer_id", "source_subject"], name: "idx_commerce_network_account", unique: true
    t.index ["peer_id"], name: "index_lightek_commerce_network_accounts_on_peer_id"
    t.index ["site_id"], name: "index_lightek_commerce_network_accounts_on_site_id"
    t.index ["user_id"], name: "index_lightek_commerce_network_accounts_on_user_id"
  end

  create_table "lightek_commerce_network_sales", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "order_id", null: false
    t.bigint "source_shipping_quote_id"
    t.string "public_key", null: false
    t.string "source_key", null: false
    t.jsonb "source_snapshot", default: {}, null: false
    t.string "return_url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_lightek_commerce_network_sales_on_order_id", unique: true
    t.index ["peer_id", "source_key"], name: "idx_commerce_network_sale", unique: true
    t.index ["peer_id"], name: "index_lightek_commerce_network_sales_on_peer_id"
    t.index ["public_key"], name: "index_lightek_commerce_network_sales_on_public_key", unique: true
    t.index ["source_shipping_quote_id"], name: "idx_network_shipping_source", unique: true
  end

  create_table "lightek_commerce_order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.integer "quantity", null: false
    t.integer "unit_price_cents", null: false
    t.integer "line_total_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id"
    t.jsonb "purchase_snapshot", default: {}, null: false
    t.index ["order_id"], name: "index_lightek_commerce_order_items_on_order_id"
    t.index ["product_id"], name: "index_lightek_commerce_order_items_on_product_id"
    t.index ["variant_id"], name: "index_lightek_commerce_order_items_on_variant_id"
    t.check_constraint "quantity > 0 AND unit_price_cents >= 0 AND line_total_cents >= 0", name: "commerce_item_amounts_valid"
  end

  create_table "lightek_commerce_orders", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "status", default: "pending_payment", null: false
    t.string "customer_email", null: false
    t.string "currency", default: "usd", null: false
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "shipping_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.integer "total_cents", default: 0, null: false
    t.string "payment_provider"
    t.string "payment_reference"
    t.datetime "paid_at"
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "refunded_cents", default: 0, null: false
    t.datetime "confirmation_sent_at"
    t.datetime "fulfilled_at"
    t.string "fulfillment_reference", limit: 160
    t.text "fulfillment_note"
    t.datetime "fulfillment_notification_sent_at"
    t.string "merchant_transfer_ref"
    t.integer "merchant_transfer_amount_cents"
    t.datetime "merchant_transfer_requested_at"
    t.datetime "merchant_transfer_completed_at"
    t.text "merchant_transfer_error"
    t.bigint "provisioning_request_id"
    t.string "provisioning_state"
    t.text "provisioning_error"
    t.datetime "provisioned_at"
    t.string "client_checkout_key", limit: 64
    t.string "payment_namespace"
    t.string "purpose", default: "purchase", null: false
    t.boolean "stock_reserved", default: true, null: false
    t.string "hosting_domain"
    t.bigint "hosting_owner_id"
    t.bigint "gatekeeper_application_launch_id"
    t.jsonb "revenue_share_snapshot", default: [], null: false
    t.bigint "shipping_quote_id"
    t.string "network_reference"
    t.string "network_invoice_reference"
    t.bigint "agency_demo_id"
    t.jsonb "demo_content", default: {}, null: false
    t.datetime "deleted_at"
    t.bigint "growth_visit_id"
    t.jsonb "buyer_fee_snapshot", default: {}, null: false
    t.string "buyer_fee_transfer_destination"
    t.datetime "buyer_fee_reversal_requested_at"
    t.string "buyer_fee_reversal_ref"
    t.integer "discount_cents", default: 0, null: false
    t.string "discount_name"
    t.bigint "storefront_buyer_id"
    t.string "gift_store_scope"
    t.integer "gift_applied_cents", default: 0, null: false
    t.index ["site_id", "storefront_buyer_id"], name: "idx_commerce_orders_store_buyer"
    t.index ["site_id", "storefront_buyer_id"], name: "idx_commerce_orders_storefront_buyer"
    t.index ["agency_demo_id"], name: "index_lightek_commerce_orders_on_agency_demo_id"
    t.index ["customer_email", "client_checkout_key"], name: "idx_commerce_client_checkout_key", unique: true, where: "(client_checkout_key IS NOT NULL)"
    t.index ["gatekeeper_application_launch_id"], name: "idx_on_gatekeeper_application_launch_id_aa7421ca02"
    t.index ["growth_visit_id"], name: "index_lightek_commerce_orders_on_growth_visit_id"
    t.index ["hosting_owner_id"], name: "index_lightek_commerce_orders_on_hosting_owner_id"
    t.index ["merchant_transfer_ref"], name: "index_lightek_commerce_orders_on_merchant_transfer_ref", unique: true
    t.index ["network_reference", "network_invoice_reference"], name: "idx_commerce_network_receipt", unique: true
    t.index ["provisioning_request_id"], name: "index_lightek_commerce_orders_on_provisioning_request_id"
    t.index ["shipping_quote_id"], name: "idx_shipping_quote_checkout", unique: true, where: "((shipping_quote_id IS NOT NULL) AND ((purpose IS NULL) OR ((purpose)::text <> 'shipping_label'::text)))"
    t.index ["shipping_quote_id"], name: "index_lightek_commerce_orders_on_shipping_quote_id"
    t.index ["site_id", "deleted_at"], name: "idx_commerce_visible_orders"
    t.index ["site_id", "payment_reference"], name: "idx_commerce_payment_reference", unique: true, where: "(payment_reference IS NOT NULL)"
    t.index ["site_id"], name: "index_lightek_commerce_orders_on_site_id"
    t.check_constraint "refunded_cents >= 0 AND refunded_cents <= total_cents", name: "commerce_refunded_amount_valid"
    t.check_constraint "subtotal_cents >= 0 AND shipping_cents >= 0 AND tax_cents >= 0 AND total_cents >= 0", name: "commerce_order_amounts_valid"
  end

  create_table "lightek_commerce_product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.string "sku"
    t.integer "price_cents", null: false
    t.integer "inventory_quantity", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "sku"], name: "index_commerce_variants_product_sku", unique: true, where: "(sku IS NOT NULL)"
    t.index ["product_id"], name: "index_lightek_commerce_product_variants_on_product_id"
  end

  create_table "lightek_commerce_products", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", limit: 160, null: false
    t.string "slug", limit: 180, null: false
    t.text "description"
    t.integer "price_cents", default: 0, null: false
    t.string "currency", limit: 3, default: "usd", null: false
    t.integer "inventory_quantity", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_url", limit: 1200
    t.string "sku", limit: 100
    t.string "product_type", default: "physical", null: false
    t.string "short_description", limit: 300
    t.integer "compare_at_cents"
    t.boolean "featured", default: false, null: false
    t.bigint "subscription_plan_id"
    t.string "billing_interval", default: "one_time", null: false
    t.boolean "track_inventory", default: true, null: false
    t.decimal "shipping_weight_lb", precision: 10, scale: 3
    t.integer "shipping_length_in"
    t.integer "shipping_width_in"
    t.integer "shipping_height_in"
    t.bigint "source_hosting_package_id"
    t.jsonb "package_policy", default: {}, null: false
    t.index ["site_id", "sku"], name: "idx_commerce_site_sku", unique: true, where: "(sku IS NOT NULL)"
    t.index ["site_id", "slug"], name: "index_lightek_commerce_products_on_site_id_and_slug", unique: true
    t.index ["site_id"], name: "index_lightek_commerce_products_on_site_id"
    t.index ["source_hosting_package_id"], name: "index_lightek_commerce_products_on_source_hosting_package_id"
    t.index ["subscription_plan_id"], name: "index_lightek_commerce_products_on_subscription_plan_id"
    t.check_constraint "compare_at_cents IS NULL OR compare_at_cents >= 0", name: "commerce_compare_price_valid"
    t.check_constraint "inventory_quantity >= 0", name: "commerce_inventory_nonnegative"
    t.check_constraint "price_cents >= 0", name: "commerce_price_nonnegative"
  end

  create_table "lightek_commerce_refunds", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.integer "amount_cents", null: false
    t.string "processor_ref"
    t.string "status", default: "pending", null: false
    t.string "idempotency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "gift_restore_cents", default: 0, null: false
    t.index ["idempotency_key"], name: "index_lightek_commerce_refunds_on_idempotency_key", unique: true
    t.index ["order_id"], name: "index_lightek_commerce_refunds_on_order_id"
    t.index ["processor_ref"], name: "index_lightek_commerce_refunds_on_processor_ref", unique: true
    t.check_constraint "amount_cents > 0", name: "commerce_refund_positive"
  end

  create_table "lightek_commerce_revenue_allocations", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "beneficiary_id", null: false
    t.integer "basis_points", null: false
    t.integer "amount_cents", null: false
    t.integer "reversed_cents", default: 0, null: false
    t.string "currency", default: "usd", null: false
    t.string "status", default: "pending", null: false
    t.string "transfer_reference"
    t.datetime "settled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["beneficiary_id"], name: "index_lightek_commerce_revenue_allocations_on_beneficiary_id"
    t.index ["order_id", "beneficiary_id"], name: "idx_revenue_order_beneficiary", unique: true
    t.index ["order_id"], name: "index_lightek_commerce_revenue_allocations_on_order_id"
    t.check_constraint "amount_cents >= 0 AND basis_points >= 0 AND basis_points <= 10000", name: "revenue_allocation_amount_valid"
  end

  create_table "lightek_commerce_subscriptions", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "processor_reference", null: false
    t.string "customer_reference"
    t.string "status", default: "incomplete", null: false
    t.string "billing_interval", null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.integer "amount_cents", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "current_period_end"
    t.datetime "last_event_at"
    t.bigint "bank_subscription_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "current_period_start"
    t.index ["bank_subscription_id"], name: "idx_commerce_bank_subscription"
    t.index ["order_id"], name: "index_lightek_commerce_subscriptions_on_order_id", unique: true
    t.index ["processor_reference"], name: "index_lightek_commerce_subscriptions_on_processor_reference", unique: true
  end

  create_table "lightek_communications_service_events", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.bigint "operator_id"
    t.bigint "billing_invoice_id"
    t.string "action", null: false
    t.jsonb "evidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_invoice_id"], name: "idx_communications_event_invoice"
    t.index ["operator_id"], name: "index_lightek_communications_service_events_on_operator_id"
    t.index ["service_id"], name: "idx_communications_service_events"
  end

  create_table "lightek_communications_services", force: :cascade do |t|
    t.bigint "subscription_id", null: false
    t.string "kind", null: false
    t.string "status", default: "provisioning", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id"], name: "idx_communications_service_subscription", unique: true
  end

  create_table "lightek_community_engagements", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.bigint "profile_id", null: false
    t.string "kind", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "profile_id", "kind"], name: "idx_community_engagement_unique", unique: true
    t.index ["post_id"], name: "index_lightek_community_engagements_on_post_id"
    t.index ["profile_id"], name: "index_lightek_community_engagements_on_profile_id"
  end

  create_table "lightek_community_memberships", force: :cascade do |t|
    t.bigint "community_id", null: false
    t.bigint "profile_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["community_id", "profile_id"], name: "idx_community_member_unique", unique: true
    t.index ["community_id"], name: "index_lightek_community_memberships_on_community_id"
    t.index ["profile_id"], name: "index_lightek_community_memberships_on_profile_id"
  end

  create_table "lightek_compliance_monitors", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "actor_id", null: false
    t.string "state", null: false
    t.string "provider", null: false
    t.string "query", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "next_run_at", null: false
    t.datetime "last_checked_at"
    t.string "error_code"
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_compliance_monitors_on_actor_id"
    t.index ["employer_id"], name: "index_lightek_compliance_monitors_on_employer_id"
  end

  create_table "lightek_connect_connections", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "platform", null: false
    t.string "label", null: false
    t.string "code_digest"
    t.datetime "code_expires_at"
    t.string "token_digest"
    t.string "external_identity"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_lightek_connect_connections_on_code_digest", unique: true
    t.index ["token_digest"], name: "index_lightek_connect_connections_on_token_digest", unique: true
    t.index ["user_id"], name: "index_lightek_connect_connections_on_user_id"
  end

  create_table "lightek_connect_events", force: :cascade do |t|
    t.bigint "connection_id"
    t.string "action", null: false
    t.string "resource"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_lightek_connect_events_on_connection_id"
  end

  create_table "lightek_connect_grants", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "destination", default: "/dashboard", null: false
    t.bigint "site_id"
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "authorization_session_id"
    t.datetime "approved_at"
    t.datetime "delegation_expires_at"
    t.index ["authorization_session_id"], name: "index_lightek_connect_grants_on_authorization_session_id"
    t.index ["code_digest"], name: "index_lightek_connect_grants_on_code_digest", unique: true
    t.index ["connection_id"], name: "index_lightek_connect_grants_on_connection_id"
    t.index ["site_id"], name: "index_lightek_connect_grants_on_site_id"
  end

  create_table "lightek_connect_sandboxes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "gatekeeper_node_id", null: false
    t.string "key", null: false
    t.string "domain", null: false
    t.string "status", default: "queued", null: false
    t.string "credential_slug", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_lightek_connect_sandboxes_on_domain", unique: true
    t.index ["gatekeeper_node_id"], name: "index_lightek_connect_sandboxes_on_gatekeeper_node_id"
    t.index ["key"], name: "index_lightek_connect_sandboxes_on_key", unique: true
    t.index ["user_id"], name: "index_lightek_connect_sandboxes_on_user_id"
  end

  create_table "lightek_discovery_channel_holds", force: :cascade do |t|
    t.bigint "matter_id", null: false
    t.bigint "channel_id", null: false
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_lightek_discovery_channel_holds_on_channel_id"
    t.index ["matter_id", "channel_id"], name: "idx_on_matter_id_channel_id_126201b550", unique: true
  end

  create_table "lightek_discovery_drive_holds", force: :cascade do |t|
    t.bigint "matter_id", null: false
    t.bigint "drive_id", null: false
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["drive_id"], name: "index_lightek_discovery_drive_holds_on_drive_id"
    t.index ["matter_id", "drive_id"], name: "index_lightek_discovery_drive_holds_on_matter_id_and_drive_id", unique: true
  end

  create_table "lightek_experiment_assignments", force: :cascade do |t|
    t.bigint "experiment_id", null: false
    t.string "visitor_digest", null: false
    t.string "arm", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["experiment_id", "visitor_digest"], name: "idx_lightek_experiment_visitor", unique: true
    t.index ["experiment_id"], name: "index_lightek_experiment_assignments_on_experiment_id"
    t.index ["visitor_digest"], name: "index_lightek_experiment_assignments_on_visitor_digest"
  end

  create_table "lightek_experiment_outcomes", force: :cascade do |t|
    t.bigint "assignment_id", null: false
    t.string "event", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_id", "event", "record_id"], name: "idx_lightek_experiment_event", unique: true
    t.index ["assignment_id"], name: "index_lightek_experiment_outcomes_on_assignment_id"
  end

  create_table "lightek_experiments", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.string "name", null: false
    t.string "surface", null: false
    t.string "target", default: "", null: false
    t.string "control", null: false
    t.string "challenger", null: false
    t.datetime "finished_at"
    t.string "winner"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "id"], name: "index_lightek_experiments_on_site_id_and_id"
    t.index ["site_id", "surface", "target"], name: "idx_lightek_running_experiment", unique: true, where: "(finished_at IS NULL)"
  end

  create_table "lightek_feature_flag_changes", force: :cascade do |t|
    t.bigint "flag_id", null: false
    t.bigint "actor_id", null: false
    t.jsonb "previous", null: false
    t.jsonb "current", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_feature_flag_changes_on_actor_id"
    t.index ["flag_id"], name: "index_lightek_feature_flag_changes_on_flag_id"
  end

  create_table "lightek_feature_flags", force: :cascade do |t|
    t.string "key", null: false
    t.boolean "enabled", default: false, null: false
    t.boolean "staff", default: false, null: false
    t.integer "percentage", default: 0, null: false
    t.jsonb "account_ids", default: [], null: false
    t.jsonb "agency_ids", default: [], null: false
    t.jsonb "installation_ids", default: [], null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_lightek_feature_flags_on_key", unique: true
    t.check_constraint "percentage >= 0 AND percentage <= 100", name: "feature_flags_valid_percentage"
  end

  create_table "lightek_full_packages", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "buyer_id", null: false
    t.string "peer_ip", null: false
    t.string "tunnel_secret_slug", null: false
    t.string "voice_secret_slug", null: false
    t.string "group_id", null: false
    t.string "request_key", null: false
    t.datetime "tunnel_ready_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_lightek_full_packages_on_buyer_id"
    t.index ["order_id"], name: "index_lightek_full_packages_on_order_id", unique: true
    t.index ["peer_ip"], name: "index_lightek_full_packages_on_peer_ip", unique: true
  end

  create_table "lightek_growth_audit_findings", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "website_audit_id", null: false
    t.bigint "page_id", null: false
    t.string "rule", null: false
    t.string "locator", null: false
    t.string "severity", null: false
    t.string "title", null: false
    t.string "status", default: "open", null: false
    t.jsonb "evidence", default: {}, null: false
    t.jsonb "fix_target", default: {}, null: false
    t.text "resolution_note"
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resolved_by_id"], name: "index_lightek_growth_audit_findings_on_resolved_by_id"
    t.index ["site_id"], name: "index_lightek_growth_audit_findings_on_site_id"
    t.index ["website_audit_id"], name: "index_lightek_growth_audit_findings_on_website_audit_id"
  end

  create_table "lightek_growth_audit_fixes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "finding_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "applied_by_id"
    t.bigint "rolled_back_by_id"
    t.string "status", default: "prepared", null: false
    t.string "baseline"
    t.string "applied_fingerprint"
    t.jsonb "before_values", default: {}, null: false
    t.jsonb "after_values", default: {}, null: false
    t.jsonb "verification", default: {}, null: false
    t.datetime "applied_at"
    t.datetime "rolled_back_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["applied_by_id"], name: "index_lightek_growth_audit_fixes_on_applied_by_id"
    t.index ["created_by_id"], name: "index_lightek_growth_audit_fixes_on_created_by_id"
    t.index ["finding_id"], name: "index_lightek_growth_audit_fixes_on_finding_id"
    t.index ["rolled_back_by_id"], name: "index_lightek_growth_audit_fixes_on_rolled_back_by_id"
    t.index ["site_id"], name: "index_lightek_growth_audit_fixes_on_site_id"
  end

  create_table "lightek_growth_backlinks", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "updated_by_id", null: false
    t.string "fingerprint", null: false
    t.text "source_url", null: false
    t.text "target_url", null: false
    t.string "status", null: false
    t.text "outreach_draft"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "fingerprint"], name: "index_lightek_growth_backlinks_on_site_id_and_fingerprint", unique: true
  end

  create_table "lightek_growth_briefs", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "updated_by_id", null: false
    t.text "offering"
    t.text "audience"
    t.text "customer_problem"
    t.text "value_proposition"
    t.text "voice"
    t.text "goal"
    t.date "goal_on"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_lightek_growth_briefs_on_site_id", unique: true
    t.index ["updated_by_id"], name: "index_lightek_growth_briefs_on_updated_by_id"
  end

  create_table "lightek_growth_comparison_arms", force: :cascade do |t|
    t.bigint "comparison_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "link_id", null: false
    t.string "label", null: false
    t.string "content_digest", null: false
    t.jsonb "creative_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_lightek_growth_comparison_arms_on_campaign_id"
    t.index ["comparison_id", "label"], name: "idx_growth_comparison_arm", unique: true
    t.index ["comparison_id"], name: "index_lightek_growth_comparison_arms_on_comparison_id"
    t.index ["link_id"], name: "index_lightek_growth_comparison_arms_on_link_id", unique: true
  end

  create_table "lightek_growth_comparisons", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.string "request_key", null: false
    t.string "name", null: false
    t.string "variable", null: false
    t.text "hypothesis", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.jsonb "brief_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_lightek_growth_comparisons_on_created_by_id"
    t.index ["site_id", "request_key"], name: "idx_growth_comparison_request", unique: true
    t.index ["site_id"], name: "index_lightek_growth_comparisons_on_site_id"
  end

  create_table "lightek_growth_demo_exposures", force: :cascade do |t|
    t.bigint "showcase_id", null: false
    t.bigint "visit_id", null: false
    t.string "variant", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["showcase_id", "visit_id"], name: "idx_on_showcase_id_visit_id_a7f577874d", unique: true
    t.index ["showcase_id"], name: "index_lightek_growth_demo_exposures_on_showcase_id"
    t.index ["visit_id"], name: "index_lightek_growth_demo_exposures_on_visit_id"
  end

  create_table "lightek_growth_feature_clips", force: :cascade do |t|
    t.bigint "feature_showcase_id", null: false
    t.integer "position", null: false
    t.string "feature_key", null: false
    t.string "category", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_showcase_id", "position"], name: "idx_feature_clip_position", unique: true
  end

  create_table "lightek_growth_feature_showcases", force: :cascade do |t|
    t.bigint "marketing_kit_id", null: false
    t.bigint "site_id", null: false
    t.bigint "page_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "approved_by_id"
    t.string "status", default: "pending", null: false
    t.string "token", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.text "error"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "demo_experiment_started_at"
    t.index ["approved_by_id"], name: "index_lightek_growth_feature_showcases_on_approved_by_id"
    t.index ["created_by_id"], name: "index_lightek_growth_feature_showcases_on_created_by_id"
    t.index ["marketing_kit_id"], name: "index_lightek_growth_feature_showcases_on_marketing_kit_id", unique: true
    t.index ["page_id"], name: "index_lightek_growth_feature_showcases_on_page_id"
    t.index ["site_id"], name: "index_lightek_growth_feature_showcases_on_site_id"
    t.index ["token"], name: "index_lightek_growth_feature_showcases_on_token", unique: true
  end

  create_table "lightek_growth_links", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "created_by_id", null: false
    t.string "token", null: false
    t.string "label", null: false
    t.string "source", null: false
    t.string "medium", null: false
    t.string "destination_path", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_lightek_growth_links_on_campaign_id"
    t.index ["created_by_id"], name: "index_lightek_growth_links_on_created_by_id"
    t.index ["site_id"], name: "index_lightek_growth_links_on_site_id"
    t.index ["token"], name: "index_lightek_growth_links_on_token", unique: true
  end

  create_table "lightek_growth_marketing_check_ins", force: :cascade do |t|
    t.bigint "marketing_kit_id", null: false
    t.bigint "actor_id", null: false
    t.integer "day_index", null: false
    t.string "status", null: false
    t.text "note", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_growth_marketing_check_ins_on_actor_id"
    t.index ["marketing_kit_id", "day_index"], name: "idx_marketing_kit_day", unique: true
  end

  create_table "lightek_growth_marketing_executions", force: :cascade do |t|
    t.bigint "marketing_kit_id", null: false
    t.bigint "actor_id", null: false
    t.bigint "goal_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_growth_marketing_executions_on_actor_id"
    t.index ["goal_id"], name: "index_lightek_growth_marketing_executions_on_goal_id"
    t.index ["marketing_kit_id"], name: "index_lightek_growth_marketing_executions_on_marketing_kit_id", unique: true
  end

  create_table "lightek_growth_marketing_kits", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "campaign_id", null: false
    t.string "request_key", null: false
    t.date "starts_on", null: false
    t.jsonb "options", default: {}, null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_lightek_growth_marketing_kits_on_campaign_id"
    t.index ["created_by_id"], name: "index_lightek_growth_marketing_kits_on_created_by_id"
    t.index ["site_id", "request_key"], name: "idx_marketing_kit_request", unique: true
    t.index ["site_id"], name: "index_lightek_growth_marketing_kits_on_site_id"
  end

  create_table "lightek_growth_page_metadata", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "page_id", null: false
    t.bigint "updated_by_id", null: false
    t.string "title_tag"
    t.text "description"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id"], name: "index_lightek_growth_page_metadata_on_page_id", unique: true
    t.index ["site_id"], name: "index_lightek_growth_page_metadata_on_site_id"
    t.index ["updated_by_id"], name: "index_lightek_growth_page_metadata_on_updated_by_id"
  end

  create_table "lightek_growth_performance_drafts", force: :cascade do |t|
    t.bigint "review_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_lightek_growth_performance_drafts_on_campaign_id"
    t.index ["created_by_id"], name: "index_lightek_growth_performance_drafts_on_created_by_id"
    t.index ["review_id"], name: "index_lightek_growth_performance_drafts_on_review_id", unique: true
  end

  create_table "lightek_growth_performance_reviews", force: :cascade do |t|
    t.bigint "comparison_id", null: false
    t.bigint "created_by_id", null: false
    t.string "request_key", null: false
    t.string "rules_version", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "measured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["comparison_id", "request_key"], name: "idx_growth_performance_review_request", unique: true
    t.index ["comparison_id"], name: "index_lightek_growth_performance_reviews_on_comparison_id"
    t.index ["created_by_id"], name: "index_lightek_growth_performance_reviews_on_created_by_id"
  end

  create_table "lightek_growth_plans", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "previous_plan_id"
    t.date "plan_on", null: false
    t.integer "revision", default: 1, null: false
    t.string "request_key", null: false
    t.string "playbook_version", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_lightek_growth_plans_on_created_by_id"
    t.index ["previous_plan_id"], name: "index_lightek_growth_plans_on_previous_plan_id"
    t.index ["site_id", "plan_on", "revision"], name: "idx_growth_plan_revision", unique: true
    t.index ["site_id", "request_key"], name: "idx_growth_plan_request", unique: true
    t.index ["site_id"], name: "index_lightek_growth_plans_on_site_id"
  end

  create_table "lightek_growth_search_snapshots", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.string "property", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.json "rows", null: false
    t.json "inspection"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_lightek_growth_search_snapshots_on_site_id"
  end

  create_table "lightek_growth_steps", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "plan_id", null: false
    t.string "key", null: false
    t.integer "position", null: false
    t.jsonb "definition", default: {}, null: false
    t.string "status", default: "open", null: false
    t.text "resolution_note"
    t.string "resolution_source"
    t.bigint "resolved_by_id"
    t.datetime "resolved_at"
    t.jsonb "result", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["plan_id", "key"], name: "index_lightek_growth_steps_on_plan_id_and_key", unique: true
    t.index ["plan_id"], name: "index_lightek_growth_steps_on_plan_id"
    t.index ["resolved_by_id"], name: "index_lightek_growth_steps_on_resolved_by_id"
    t.index ["site_id"], name: "index_lightek_growth_steps_on_site_id"
  end

  create_table "lightek_growth_visits", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "link_id", null: false
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["link_id"], name: "index_lightek_growth_visits_on_link_id"
    t.index ["site_id", "created_at"], name: "index_lightek_growth_visits_on_site_id_and_created_at"
    t.index ["site_id"], name: "index_lightek_growth_visits_on_site_id"
    t.index ["token"], name: "index_lightek_growth_visits_on_token", unique: true
  end

  create_table "lightek_growth_website_audits", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "scope_page_id"
    t.string "request_key", null: false
    t.string "status", null: false
    t.string "rules_version", null: false
    t.jsonb "page_results", default: [], null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_lightek_growth_website_audits_on_created_by_id"
    t.index ["site_id", "request_key"], name: "idx_website_audit_request", unique: true
    t.index ["site_id"], name: "index_lightek_growth_website_audits_on_site_id"
  end

  create_table "lightek_growth_website_changes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "action_id", null: false
    t.bigint "actor_id", null: false
    t.string "operation", null: false
    t.json "previous_source"
    t.json "result", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_lightek_growth_website_changes_on_action_id", unique: true
    t.index ["site_id"], name: "index_lightek_growth_website_changes_on_site_id"
  end

  create_table "lightek_identity_connections", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "slug", null: false
    t.string "issuer", null: false
    t.string "authorization_endpoint", null: false
    t.string "token_endpoint", null: false
    t.string "jwks_uri", null: false
    t.string "client_id", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_identity_connections_on_employer_id", unique: true
    t.index ["slug"], name: "index_lightek_identity_connections_on_slug", unique: true
  end

  create_table "lightek_identity_factors", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "secret_box", default: {}, null: false
    t.jsonb "recovery_digests", default: [], null: false
    t.datetime "enabled_at"
    t.datetime "expires_at"
    t.bigint "last_counter", default: -1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_lightek_identity_factors_on_user_id", unique: true
  end

  create_table "lightek_identity_login_attempts", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "user_id"
    t.string "state_digest", null: false
    t.string "browser_digest", null: false
    t.jsonb "secret_box", default: {}, null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id"], name: "index_lightek_identity_login_attempts_on_connection_id"
    t.index ["state_digest"], name: "index_lightek_identity_login_attempts_on_state_digest", unique: true
    t.index ["user_id"], name: "index_lightek_identity_login_attempts_on_user_id"
  end

  create_table "lightek_identity_node_bindings", force: :cascade do |t|
    t.bigint "realm_id", null: false
    t.bigint "gatekeeper_node_id", null: false
    t.bigint "synced_revision", default: -1, null: false
    t.string "policy_digest"
    t.string "status", default: "pending", null: false
    t.string "error_code"
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gatekeeper_node_id"], name: "index_lightek_identity_node_bindings_on_gatekeeper_node_id", unique: true
    t.index ["realm_id"], name: "index_lightek_identity_node_bindings_on_realm_id"
  end

  create_table "lightek_identity_organization_policies", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.boolean "mfa_required", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "connect_mfa_allowed", default: true, null: false
    t.index ["employer_id"], name: "index_lightek_identity_organization_policies_on_employer_id", unique: true
  end

  create_table "lightek_identity_realms", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "domain", null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "auto_join", default: false, null: false
    t.bigint "directory_revision", default: 0, null: false
    t.date "calendar_on"
    t.datetime "next_sync_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_identity_realms_on_employer_id", unique: true
  end

  create_table "lightek_identity_resource_grants", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "resource_type", null: false
    t.bigint "resource_id", null: false
    t.string "permission", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id", "subject_type", "subject_id", "resource_type", "resource_id", "permission"], name: "idx_directory_grant", unique: true
    t.index ["employer_id"], name: "index_lightek_identity_resource_grants_on_employer_id"
  end

  create_table "lightek_identity_subjects", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "user_id", null: false
    t.string "subject", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "subject"], name: "idx_identity_subject", unique: true
    t.index ["connection_id", "user_id"], name: "idx_identity_user", unique: true
    t.index ["connection_id"], name: "index_lightek_identity_subjects_on_connection_id"
    t.index ["user_id"], name: "index_lightek_identity_subjects_on_user_id"
  end

  create_table "lightek_live_viewers", force: :cascade do |t|
    t.bigint "studio_live_operation_id", null: false
    t.bigint "user_id", null: false
    t.datetime "last_seen_at", null: false
    t.index ["last_seen_at"], name: "index_lightek_live_viewers_on_last_seen_at"
    t.index ["studio_live_operation_id", "user_id"], name: "idx_lightek_live_viewer_identity", unique: true
    t.index ["studio_live_operation_id"], name: "index_lightek_live_viewers_on_studio_live_operation_id"
    t.index ["user_id"], name: "index_lightek_live_viewers_on_user_id"
  end

  create_table "lightek_mail_accounts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "domain_id", null: false
    t.string "address", null: false
    t.string "display_name", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "daily_limit", default: 100, null: false
    t.date "send_day"
    t.integer "send_count", default: 0, null: false
    t.bigint "storage_limit", default: 1073741824, null: false
    t.string "token_digest"
    t.string "token_hint"
    t.boolean "auto_reply_enabled", default: false, null: false
    t.bigint "auto_template_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "minute_limit", default: 5, null: false
    t.integer "hour_limit", default: 25, null: false
    t.datetime "suspended_at"
    t.string "suspension_reason"
    t.string "mailbox_kind", default: "mailbox", null: false
    t.datetime "deleted_at"
    t.string "original_address"
    t.string "spam_filter_level", default: "standard", null: false
    t.json "allowed_senders", default: [], null: false
    t.json "blocked_senders", default: [], null: false
    t.boolean "brand_member", default: false, null: false
    t.bigint "installation_peer_id"
    t.index ["address"], name: "index_lightek_mail_accounts_on_address", unique: true
    t.index ["domain_id"], name: "index_lightek_mail_accounts_on_domain_id"
    t.index ["installation_peer_id"], name: "index_lightek_mail_accounts_on_installation_peer_id", unique: true
    t.index ["token_digest"], name: "index_lightek_mail_accounts_on_token_digest", unique: true
    t.index ["user_id"], name: "index_lightek_mail_accounts_on_user_id"
  end

  create_table "lightek_mail_auto_replies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sender", null: false
    t.date "day", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "sender", "day"], name: "idx_mail_auto_once", unique: true
    t.index ["account_id"], name: "index_lightek_mail_auto_replies_on_account_id"
  end

  create_table "lightek_mail_calendar_history_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "uid", limit: 255, null: false
    t.string "occurrence_key", limit: 32, default: "", null: false
    t.string "title", limit: 160, null: false
    t.string "location", limit: 300
    t.text "description"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.boolean "all_day", default: false, null: false
    t.boolean "cancelled", default: false, null: false
    t.string "zone"
    t.string "rule"
    t.jsonb "added_dates", default: [], null: false
    t.jsonb "excluded_dates", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "starts_at"], name: "idx_mail_history_calendar_dates"
    t.index ["account_id", "uid", "occurrence_key"], name: "idx_mail_history_event_identity", unique: true
    t.index ["account_id"], name: "index_lightek_mail_calendar_history_events_on_account_id"
  end

  create_table "lightek_mail_calendar_history_previews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "team_mailbox_id"
    t.jsonb "events", default: [], null: false
    t.jsonb "issues", default: [], null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lightek_mail_calendar_history_previews_on_account_id"
    t.index ["expires_at"], name: "index_lightek_mail_calendar_history_previews_on_expires_at"
    t.index ["team_mailbox_id"], name: "idx_on_team_mailbox_id_ba9c41c2a6"
  end

  create_table "lightek_mail_calendar_invitations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "source_message_id"
    t.bigint "reply_message_id"
    t.string "uid", limit: 255, null: false
    t.string "organizer", limit: 254, null: false
    t.string "attendee", limit: 254, null: false
    t.string "title", limit: 160, null: false
    t.text "description"
    t.string "location", limit: 300
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "all_day", default: false, null: false
    t.integer "sequence", null: false
    t.datetime "stamp", null: false
    t.string "response", default: "pending", null: false
    t.datetime "reply_stamp"
    t.integer "response_revision", default: 0, null: false
    t.boolean "cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "attendee", "organizer", "uid"], name: "idx_mail_calendar_invitation_identity", unique: true
    t.index ["account_id", "attendee", "starts_at"], name: "idx_mail_calendar_invitation_agenda"
    t.index ["reply_message_id"], name: "index_lightek_mail_calendar_invitations_on_reply_message_id"
    t.index ["source_message_id"], name: "index_lightek_mail_calendar_invitations_on_source_message_id"
  end

  create_table "lightek_mail_contact_previews", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "team_mailbox_id"
    t.jsonb "contacts", default: [], null: false
    t.integer "invalid_rows", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lightek_mail_contact_previews_on_account_id"
    t.index ["expires_at"], name: "index_lightek_mail_contact_previews_on_expires_at"
    t.index ["team_mailbox_id"], name: "index_lightek_mail_contact_previews_on_team_mailbox_id"
  end

  create_table "lightek_mail_contacts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 200, null: false
    t.string "import_key", limit: 64, null: false
    t.jsonb "source_emails", default: [], null: false
    t.jsonb "emails", default: [], null: false
    t.jsonb "phones", default: [], null: false
    t.jsonb "labels", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "import_key"], name: "idx_mail_contact_import_identity", unique: true
    t.index ["account_id"], name: "index_lightek_mail_contacts_on_account_id"
  end

  create_table "lightek_mail_customer_suspensions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "reason", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_lightek_mail_customer_suspensions_on_user_id", unique: true
  end

  create_table "lightek_mail_discovery_events", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "matter_id"
    t.bigint "account_id"
    t.bigint "actor_id"
    t.string "action", null: false
    t.json "details", default: {}, null: false
    t.integer "result_count"
    t.datetime "created_at", null: false
    t.bigint "drive_id"
    t.bigint "channel_id"
    t.index ["account_id"], name: "index_lightek_mail_discovery_events_on_account_id"
    t.index ["actor_id"], name: "index_lightek_mail_discovery_events_on_actor_id"
    t.index ["channel_id"], name: "index_lightek_mail_discovery_events_on_channel_id"
    t.index ["drive_id"], name: "index_lightek_mail_discovery_events_on_drive_id"
    t.index ["employer_id", "created_at"], name: "idx_mail_discovery_activity"
    t.index ["matter_id"], name: "index_lightek_mail_discovery_events_on_matter_id"
  end

  create_table "lightek_mail_domains", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "verification_token", null: false
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_lightek_mail_domains_on_name", unique: true
    t.index ["user_id"], name: "index_lightek_mail_domains_on_user_id"
  end

  create_table "lightek_mail_envelopes", force: :cascade do |t|
    t.bigint "inbound_email_id", null: false
    t.json "recipients", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "recipient_snapshots", default: {}, null: false
    t.index ["inbound_email_id"], name: "index_lightek_mail_envelopes_on_inbound_email_id", unique: true
  end

  create_table "lightek_mail_feedback_events", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "message_id", null: false
    t.string "event_key", null: false
    t.string "kind", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "idx_mail_recent_feedback"
    t.index ["account_id"], name: "index_lightek_mail_feedback_events_on_account_id"
    t.index ["event_key"], name: "index_lightek_mail_feedback_events_on_event_key", unique: true
  end

  create_table "lightek_mail_group_members", force: :cascade do |t|
    t.bigint "group_id", null: false
    t.bigint "member_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "member_id"], name: "idx_mail_group_members_unique", unique: true
    t.index ["group_id"], name: "index_lightek_mail_group_members_on_group_id"
    t.index ["member_id"], name: "index_lightek_mail_group_members_on_member_id"
  end

  create_table "lightek_mail_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "requested_by_id", null: false
    t.string "mailbox_address", null: false
    t.string "state", default: "queued", null: false
    t.string "phase", default: "preview", null: false
    t.string "run_token", null: false
    t.bigint "archive_bytes", null: false
    t.bigint "byte_offset", default: 0, null: false
    t.jsonb "preview", default: {}, null: false
    t.jsonb "results", default: {}, null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "team_mailbox_id"
    t.datetime "approved_at"
    t.index ["account_id"], name: "index_lightek_mail_imports_on_account_id"
    t.index ["requested_by_id"], name: "index_lightek_mail_imports_on_requested_by_id"
    t.index ["team_mailbox_id"], name: "index_lightek_mail_imports_on_team_mailbox_id", unique: true
  end

  create_table "lightek_mail_matter_holds", force: :cascade do |t|
    t.bigint "matter_id", null: false
    t.bigint "account_id", null: false
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lightek_mail_matter_holds_on_account_id"
    t.index ["matter_id", "account_id"], name: "index_lightek_mail_matter_holds_on_matter_id_and_account_id", unique: true
  end

  create_table "lightek_mail_matter_reviewers", force: :cascade do |t|
    t.bigint "matter_id", null: false
    t.bigint "user_id", null: false
    t.index ["matter_id", "user_id"], name: "index_lightek_mail_matter_reviewers_on_matter_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_lightek_mail_matter_reviewers_on_user_id"
  end

  create_table "lightek_mail_matters", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", limit: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_mail_matters_on_employer_id"
  end

  create_table "lightek_mail_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "direction", null: false
    t.string "state", null: false
    t.string "from_address", null: false
    t.json "to_addresses", default: [], null: false
    t.json "cc_addresses", default: [], null: false
    t.json "bcc_addresses", default: [], null: false
    t.string "subject", default: "", null: false
    t.text "text_body"
    t.text "html_body"
    t.string "message_id", null: false
    t.string "in_reply_to"
    t.string "idempotency_key"
    t.string "error_message"
    t.boolean "starred", default: false, null: false
    t.boolean "archived", default: false, null: false
    t.boolean "trashed", default: false, null: false
    t.datetime "read_at"
    t.datetime "submitted_at"
    t.bigint "bytesize", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "junk", default: false, null: false
    t.float "spam_score"
    t.string "spam_reason"
    t.datetime "spam_scanned_at"
    t.jsonb "calendar_notice", default: {}, null: false
    t.datetime "imported_at"
    t.jsonb "imported_labels", default: [], null: false
    t.index ["account_id", "created_at"], name: "idx_mail_recent"
    t.index ["account_id", "idempotency_key"], name: "idx_mail_idempotency", unique: true
    t.index ["account_id", "message_id"], name: "idx_mail_account_message_identity"
    t.index ["account_id"], name: "index_lightek_mail_messages_on_account_id"
  end

  create_table "lightek_mail_retained_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "original_id", null: false
    t.datetime "sent_or_received_at", null: false
    t.string "subject", null: false
    t.string "from_address", null: false
    t.text "text_body"
    t.json "snapshot", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "sent_or_received_at"], name: "idx_mail_retained_by_date"
    t.index ["original_id"], name: "index_lightek_mail_retained_messages_on_original_id", unique: true
  end

  create_table "lightek_mail_retention_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "days", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lightek_mail_retention_rules_on_account_id", unique: true
    t.check_constraint "days >= 1 AND days <= 36500", name: "mail_retention_days"
  end

  create_table "lightek_mail_send_reservations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "message_id", null: false
    t.integer "recipient_count", null: false
    t.datetime "reserved_at", null: false
    t.datetime "dispatched_at"
    t.index ["account_id", "reserved_at"], name: "idx_mail_account_reservations"
    t.index ["account_id"], name: "index_lightek_mail_send_reservations_on_account_id"
    t.index ["dispatched_at"], name: "index_lightek_mail_send_reservations_on_dispatched_at"
    t.index ["message_id"], name: "index_lightek_mail_send_reservations_on_message_id", unique: true
    t.index ["reserved_at"], name: "index_lightek_mail_send_reservations_on_reserved_at"
    t.index ["user_id", "reserved_at"], name: "idx_mail_customer_reservations"
    t.index ["user_id"], name: "index_lightek_mail_send_reservations_on_user_id"
    t.check_constraint "recipient_count > 0 AND recipient_count <= 20", name: "mail_recipient_count_range"
  end

  create_table "lightek_mail_sending_policies", force: :cascade do |t|
    t.boolean "sending_enabled", default: true, null: false
    t.string "stop_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "nevaeh_support_sender", default: {}, null: false
    t.check_constraint "id = 1", name: "mail_single_sending_policy"
  end

  create_table "lightek_mail_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "subject", null: false
    t.json "document", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_lightek_mail_templates_on_account_id"
  end

  create_table "lightek_managed_dns_enrollments", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "requested_by_id", null: false
    t.bigint "reviewed_by_id"
    t.string "domain", null: false
    t.string "state", default: "requested", null: false
    t.string "proof", null: false
    t.string "provider_zone_id"
    t.string "records_digest"
    t.jsonb "previous_nameservers", default: [], null: false
    t.jsonb "nameservers", default: [], null: false
    t.datetime "reviewed_at"
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider_kind", default: "cloudflare", null: false
    t.index ["domain"], name: "index_lightek_managed_dns_enrollments_on_domain", unique: true, where: "((state)::text <> 'withdrawn'::text)"
    t.index ["order_id"], name: "index_lightek_managed_dns_enrollments_on_order_id", unique: true
    t.index ["owner_id"], name: "index_lightek_managed_dns_enrollments_on_owner_id"
    t.index ["provider_zone_id"], name: "index_lightek_managed_dns_enrollments_on_provider_zone_id", unique: true, where: "((state)::text <> 'withdrawn'::text)"
    t.index ["requested_by_id"], name: "index_lightek_managed_dns_enrollments_on_requested_by_id"
    t.index ["reviewed_by_id"], name: "index_lightek_managed_dns_enrollments_on_reviewed_by_id"
    t.check_constraint "provider_kind::text = ANY (ARRAY['cloudflare'::character varying, 'powerdns'::character varying]::text[])", name: "managed_dns_provider_kind"
  end

  create_table "lightek_marketing_campaigns", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", limit: 160, null: false
    t.string "channel", default: "landing_page", null: false
    t.string "status", default: "draft", null: false
    t.string "headline", limit: 200
    t.text "message"
    t.string "cta_label", limit: 60
    t.string "cta_url", limit: 400
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "mail_account_id"
    t.string "recipient_email"
    t.datetime "sent_at"
    t.bigint "mail_message_id"
    t.integer "sequence_delay_hours", default: 0, null: false
    t.datetime "scheduled_at"
    t.datetime "dispatch_started_at"
    t.string "media_url", limit: 1200
    t.string "production_format", default: "portrait", null: false
    t.integer "lock_version", default: 0, null: false
    t.boolean "content_review_required", default: false, null: false
    t.string "approved_content_digest"
    t.bigint "content_approved_by_id"
    t.datetime "content_approved_at"
    t.bigint "media_binding_id"
    t.index ["content_approved_by_id"], name: "index_lightek_marketing_campaigns_on_content_approved_by_id"
    t.index ["mail_account_id"], name: "index_lightek_marketing_campaigns_on_mail_account_id"
    t.index ["mail_message_id"], name: "index_lightek_marketing_campaigns_on_mail_message_id"
    t.index ["media_binding_id"], name: "index_lightek_marketing_campaigns_on_media_binding_id"
    t.index ["site_id", "status"], name: "index_lightek_marketing_campaigns_on_site_id_and_status"
    t.index ["site_id"], name: "index_lightek_marketing_campaigns_on_site_id"
  end

  create_table "lightek_marketing_contacts", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "email", null: false
    t.datetime "subscribed_at"
    t.datetime "unsubscribed_at"
    t.string "consent_source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "subscription_token_digest"
    t.datetime "confirmation_sent_at"
    t.bigint "sales_account_id"
    t.bigint "sales_owner_id"
    t.string "name"
    t.string "phone"
    t.string "job_title"
    t.text "sales_notes"
    t.integer "lock_version", default: 0, null: false
    t.index ["sales_account_id"], name: "index_lightek_marketing_contacts_on_sales_account_id"
    t.index ["sales_owner_id"], name: "index_lightek_marketing_contacts_on_sales_owner_id"
    t.index ["site_id", "email"], name: "index_lightek_marketing_contacts_on_site_id_and_email", unique: true
    t.index ["site_id"], name: "index_lightek_marketing_contacts_on_site_id"
    t.index ["subscription_token_digest"], name: "index_lightek_marketing_contacts_on_subscription_token_digest", unique: true
  end

  create_table "lightek_marketing_content_variants", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "approved_by_id"
    t.string "batch_key", null: false
    t.string "angle", null: false
    t.string "status", null: false
    t.string "headline"
    t.string "cta_label"
    t.string "cta_url"
    t.string "media_url"
    t.text "message"
    t.string "applied_digest"
    t.string "baseline_digest", null: false
    t.jsonb "source_snapshot", default: {}, null: false
    t.datetime "approved_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_lightek_marketing_content_variants_on_approved_by_id"
    t.index ["campaign_id", "batch_key", "angle"], name: "idx_campaign_content_angle", unique: true
    t.index ["campaign_id"], name: "index_lightek_marketing_content_variants_on_campaign_id"
    t.index ["created_by_id"], name: "index_lightek_marketing_content_variants_on_created_by_id"
    t.index ["site_id"], name: "index_lightek_marketing_content_variants_on_site_id"
  end

  create_table "lightek_marketing_deliveries", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "mail_message_id"
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "content_digest"
    t.index ["campaign_id", "contact_id"], name: "idx_on_campaign_id_contact_id_9471603ba4", unique: true
    t.index ["campaign_id"], name: "index_lightek_marketing_deliveries_on_campaign_id"
    t.index ["contact_id"], name: "index_lightek_marketing_deliveries_on_contact_id"
    t.index ["mail_message_id"], name: "index_lightek_marketing_deliveries_on_mail_message_id"
  end

  create_table "lightek_marketing_media_bindings", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "artifact_id"
    t.bigint "created_by_id", null: false
    t.string "token", null: false
    t.string "filename", null: false
    t.string "delivery_host", null: false
    t.jsonb "source_snapshot", default: {}, null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_lightek_marketing_media_bindings_on_artifact_id"
    t.index ["campaign_id"], name: "index_lightek_marketing_media_bindings_on_campaign_id"
    t.index ["created_by_id"], name: "index_lightek_marketing_media_bindings_on_created_by_id"
    t.index ["site_id"], name: "index_lightek_marketing_media_bindings_on_site_id"
    t.index ["token"], name: "index_lightek_marketing_media_bindings_on_token", unique: true
  end

  create_table "lightek_marketing_publication_slots", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "connection_id", null: false
    t.bigint "scheduled_by_id", null: false
    t.bigint "social_post_id"
    t.string "request_key", null: false
    t.string "content_digest", null: false
    t.string "status", default: "scheduled", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "queue_requested_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "connection_id"], name: "idx_publication_slot_destination", unique: true, where: "((status)::text <> 'canceled'::text)"
    t.index ["campaign_id"], name: "index_lightek_marketing_publication_slots_on_campaign_id"
    t.index ["connection_id"], name: "index_lightek_marketing_publication_slots_on_connection_id"
    t.index ["scheduled_by_id"], name: "index_lightek_marketing_publication_slots_on_scheduled_by_id"
    t.index ["site_id", "request_key"], name: "idx_publication_slot_request", unique: true
    t.index ["site_id"], name: "index_lightek_marketing_publication_slots_on_site_id"
    t.index ["social_post_id"], name: "index_lightek_marketing_publication_slots_on_social_post_id"
    t.index ["status", "scheduled_at"], name: "idx_on_status_scheduled_at_9297f35c32"
  end

  create_table "lightek_marketing_social_connections", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "provider", null: false
    t.string "account_label", null: false
    t.string "publish_endpoint", null: false
    t.string "credential_key", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "disabled_at"
    t.index ["site_id", "provider", "account_label"], name: "idx_marketing_social_connection", unique: true
    t.index ["site_id"], name: "index_lightek_marketing_social_connections_on_site_id"
  end

  create_table "lightek_marketing_social_posts", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "connection_id", null: false
    t.string "status", default: "pending", null: false
    t.string "remote_id"
    t.text "error"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "submission_status"
    t.datetime "last_checked_at"
    t.index ["campaign_id", "connection_id"], name: "idx_marketing_social_post", unique: true
    t.index ["campaign_id"], name: "index_lightek_marketing_social_posts_on_campaign_id"
    t.index ["connection_id", "published_at"], name: "idx_social_publication_history"
    t.index ["connection_id"], name: "index_lightek_marketing_social_posts_on_connection_id"
  end

  create_table "lightek_marketplace_customer_services", force: :cascade do |t|
    t.string "name", null: false
    t.text "description", null: false
    t.string "feature_key", null: false
    t.string "customer_path", null: false
    t.boolean "active", default: false, null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "lightek_marketplace_product_groups", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "idx_marketplace_group_key", unique: true
  end

  create_table "lightek_merchant_payout_schedules", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "cadence", default: "biweekly", null: false
    t.datetime "next_run_at", null: false
    t.datetime "last_run_at"
    t.boolean "enabled", default: true, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_lightek_merchant_payout_schedules_on_merchant_id", unique: true
  end

  create_table "lightek_messaging_conversations", force: :cascade do |t|
    t.string "kind", default: "direct", null: false
    t.string "title"
    t.string "direct_key"
    t.bigint "created_by_profile_id", null: false
    t.datetime "last_message_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_profile_id"], name: "index_lightek_messaging_conversations_on_created_by_profile_id"
    t.index ["direct_key"], name: "index_lightek_messaging_conversations_on_direct_key", unique: true, where: "(direct_key IS NOT NULL)"
    t.index ["kind", "updated_at"], name: "index_lightek_messaging_conversations_on_kind_and_updated_at"
    t.check_constraint "kind::text <> 'group'::text OR title IS NOT NULL AND btrim(title::text) <> ''::text", name: "lightek_messaging_conversations_group_title_check"
    t.check_constraint "kind::text = 'direct'::text AND direct_key IS NOT NULL OR kind::text <> 'direct'::text AND direct_key IS NULL", name: "lightek_messaging_conversations_direct_key_check"
    t.check_constraint "kind::text = ANY (ARRAY['direct'::character varying, 'group'::character varying, 'community'::character varying, 'watch_party'::character varying]::text[])", name: "lightek_messaging_conversations_kind_check"
  end

  create_table "lightek_messaging_messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "sender_profile_id", null: false
    t.bigint "reply_to_message_id"
    t.string "message_type", default: "text", null: false
    t.text "body", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "idx_lightek_messaging_messages_timeline"
    t.index ["conversation_id"], name: "index_lightek_messaging_messages_on_conversation_id"
    t.index ["reply_to_message_id"], name: "index_lightek_messaging_messages_on_reply_to_message_id"
    t.index ["sender_profile_id"], name: "index_lightek_messaging_messages_on_sender_profile_id"
    t.check_constraint "char_length(btrim(body)) > 0", name: "lightek_messaging_messages_body_check"
    t.check_constraint "message_type::text = ANY (ARRAY['text'::character varying, 'system'::character varying]::text[])", name: "lightek_messaging_messages_type_check"
  end

  create_table "lightek_messaging_participants", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "profile_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "joined_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "last_read_at"
    t.datetime "left_at"
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "profile_id"], name: "idx_lightek_messaging_participants_unique", unique: true
    t.index ["conversation_id"], name: "index_lightek_messaging_participants_on_conversation_id"
    t.index ["profile_id", "left_at"], name: "idx_lightek_messaging_participants_active"
    t.index ["profile_id"], name: "index_lightek_messaging_participants_on_profile_id"
    t.check_constraint "left_at IS NULL OR left_at >= joined_at", name: "lightek_messaging_participants_left_at_check"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'member'::character varying]::text[])", name: "lightek_messaging_participants_role_check"
  end

  create_table "lightek_network_office_files", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "editor_peer_id", null: false
    t.string "key", null: false
    t.string "editor_name", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "content", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "rich_text", default: false, null: false
    t.index ["channel_id", "key"], name: "index_lightek_network_office_files_on_channel_id_and_key", unique: true
    t.index ["channel_id"], name: "index_lightek_network_office_files_on_channel_id"
    t.index ["editor_peer_id"], name: "index_lightek_network_office_files_on_editor_peer_id"
  end

  create_table "lightek_office_files", force: :cascade do |t|
    t.bigint "channel_id"
    t.bigint "creator_id", null: false
    t.bigint "editor_id", null: false
    t.string "kind", limit: 16, null: false
    t.string "title", limit: 160, null: false
    t.text "content", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "rich_text", default: false, null: false
    t.bigint "drive_entry_id"
    t.index ["channel_id"], name: "index_lightek_office_files_on_channel_id"
    t.index ["creator_id"], name: "index_lightek_office_files_on_creator_id"
    t.index ["drive_entry_id"], name: "index_lightek_office_files_on_drive_entry_id", unique: true
    t.index ["editor_id"], name: "index_lightek_office_files_on_editor_id"
    t.check_constraint "(channel_id IS NULL) <> (drive_entry_id IS NULL)", name: "office_files_have_one_location"
  end

  create_table "lightek_office_revisions", force: :cascade do |t|
    t.string "file_type", null: false
    t.bigint "file_id", null: false
    t.integer "version", null: false
    t.text "content", null: false
    t.boolean "rich_text", null: false
    t.string "title", null: false
    t.string "editor_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["file_type", "file_id", "version"], name: "index_lightek_office_revisions_on_file_and_version", unique: true
  end

  create_table "lightek_payout_connection_changes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "previous_account_id", null: false
    t.string "replacement_account_id", null: false
    t.string "platform_account_id", null: false
    t.boolean "livemode", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["replacement_account_id"], name: "idx_payout_replacement_account", unique: true
    t.index ["user_id"], name: "index_lightek_payout_connection_changes_on_user_id"
  end

  create_table "lightek_people_audit_events", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "actor_id", null: false
    t.string "action", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_people_audit_events_on_actor_id"
    t.index ["employer_id"], name: "index_lightek_people_audit_events_on_employer_id"
  end

  create_table "lightek_people_benefit_enrollments", force: :cascade do |t|
    t.bigint "employment_id", null: false
    t.bigint "benefit_plan_id", null: false
    t.date "starts_on", null: false
    t.date "ends_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["benefit_plan_id"], name: "index_lightek_people_benefit_enrollments_on_benefit_plan_id"
    t.index ["employment_id", "benefit_plan_id"], name: "idx_people_benefit_election", unique: true, where: "(ends_on IS NULL)"
    t.index ["employment_id"], name: "index_lightek_people_benefit_enrollments_on_employment_id"
  end

  create_table "lightek_people_benefit_plans", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.string "currency", default: "USD", null: false
    t.string "deduction_treatment", default: "post_tax", null: false
    t.bigint "employee_cents", default: 0, null: false
    t.bigint "employer_cents", default: 0, null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_people_benefit_plans_on_employer_id"
  end

  create_table "lightek_people_departments", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "parent_id"
    t.string "name", null: false
    t.string "code", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id", "code"], name: "index_lightek_people_departments_on_employer_id_and_code", unique: true
    t.index ["employer_id"], name: "index_lightek_people_departments_on_employer_id"
    t.index ["parent_id"], name: "index_lightek_people_departments_on_parent_id"
  end

  create_table "lightek_people_employments", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "worker_id", null: false
    t.bigint "department_id"
    t.bigint "manager_id"
    t.string "title", null: false
    t.string "level", default: "individual_contributor", null: false
    t.string "worker_kind", default: "employee", null: false
    t.boolean "active", default: true, null: false
    t.boolean "people_admin", default: false, null: false
    t.string "payroll_access", default: "none", null: false
    t.date "starts_on", null: false
    t.date "ends_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "directory_admin", default: false, null: false
    t.string "directory_principal"
    t.string "accounting_access", default: "none", null: false
    t.string "compliance_access", default: "none", null: false
    t.index ["department_id"], name: "index_lightek_people_employments_on_department_id"
    t.index ["employer_id", "directory_principal"], name: "idx_employer_directory_principal", unique: true, where: "(directory_principal IS NOT NULL)"
    t.index ["employer_id", "worker_id"], name: "idx_people_employer_worker", unique: true
    t.index ["employer_id"], name: "index_lightek_people_employments_on_employer_id"
    t.index ["manager_id"], name: "index_lightek_people_employments_on_manager_id"
    t.index ["worker_id"], name: "index_lightek_people_employments_on_worker_id"
  end

  create_table "lightek_people_lifecycle_cases", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "revoked_by_id"
    t.bigint "completed_by_id"
    t.string "kind", null: false
    t.string "status", default: "open", null: false
    t.jsonb "steps", default: {}, null: false
    t.jsonb "receipt", default: {}, null: false
    t.datetime "access_revoked_at"
    t.datetime "completed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_by_id"], name: "index_lightek_people_lifecycle_cases_on_completed_by_id"
    t.index ["created_by_id"], name: "index_lightek_people_lifecycle_cases_on_created_by_id"
    t.index ["employer_id", "subject_type", "subject_id"], name: "idx_open_lifecycle_case", unique: true, where: "((status)::text <> ALL ((ARRAY['completed'::character varying, 'canceled'::character varying])::text[]))"
    t.index ["employer_id"], name: "index_lightek_people_lifecycle_cases_on_employer_id"
    t.index ["revoked_by_id"], name: "index_lightek_people_lifecycle_cases_on_revoked_by_id"
    t.index ["subject_type", "subject_id"], name: "index_lightek_people_lifecycle_cases_on_subject"
  end

  create_table "lightek_people_pay_runs", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "prepared_by_id", null: false
    t.bigint "approved_by_id"
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.date "pay_date", null: false
    t.string "currency", default: "USD", null: false
    t.string "status", default: "draft", null: false
    t.string "financial_account_ref"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "preparation_scheduled_at"
    t.bigint "preparation_actor_id"
    t.string "preparation_token"
    t.string "preparation_state"
    t.string "preparation_error_code"
    t.index ["approved_by_id"], name: "index_lightek_people_pay_runs_on_approved_by_id"
    t.index ["employer_id", "period_start", "period_end", "pay_date"], name: "idx_people_pay_period", unique: true, where: "((status)::text <> 'canceled'::text)"
    t.index ["employer_id"], name: "index_lightek_people_pay_runs_on_employer_id"
    t.index ["preparation_actor_id"], name: "index_lightek_people_pay_runs_on_preparation_actor_id"
    t.index ["prepared_by_id"], name: "index_lightek_people_pay_runs_on_prepared_by_id"
  end

  create_table "lightek_people_pay_statements", force: :cascade do |t|
    t.bigint "pay_run_id", null: false
    t.bigint "employment_id", null: false
    t.bigint "prepared_by_id", null: false
    t.bigint "gross_cents", null: false
    t.bigint "tax_cents", default: 0, null: false
    t.bigint "employer_tax_cents", default: 0, null: false
    t.bigint "other_deductions_cents", default: 0, null: false
    t.bigint "benefit_cents", default: 0, null: false
    t.bigint "employer_benefit_cents", default: 0, null: false
    t.bigint "net_cents", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.string "tax_reference", null: false
    t.string "status", default: "draft", null: false
    t.string "provider_ref"
    t.string "provider_status"
    t.datetime "attempted_at"
    t.string "error_code"
    t.jsonb "quote", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employment_id"], name: "index_lightek_people_pay_statements_on_employment_id"
    t.index ["pay_run_id", "employment_id"], name: "idx_people_run_worker", unique: true
    t.index ["pay_run_id"], name: "index_lightek_people_pay_statements_on_pay_run_id"
    t.index ["prepared_by_id"], name: "index_lightek_people_pay_statements_on_prepared_by_id"
    t.index ["provider_ref"], name: "index_lightek_people_pay_statements_on_provider_ref", unique: true
    t.check_constraint "gross_cents >= 0 AND tax_cents >= 0 AND employer_tax_cents >= 0 AND other_deductions_cents >= 0 AND benefit_cents >= 0 AND employer_benefit_cents >= 0 AND net_cents >= 0", name: "people_payroll_nonnegative"
    t.check_constraint "net_cents = (gross_cents - tax_cents - other_deductions_cents - benefit_cents)", name: "people_payroll_net_matches"
  end

  create_table "lightek_people_payout_destinations", force: :cascade do |t|
    t.bigint "employment_id", null: false
    t.string "provider", default: "stripe_global", null: false
    t.string "recipient_ref"
    t.string "capability_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employment_id"], name: "index_lightek_people_payout_destinations_on_employment_id", unique: true
  end

  create_table "lightek_people_payout_senders", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "financial_account_ref", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_people_payout_senders_on_employer_id", unique: true
    t.index ["financial_account_ref"], name: "index_lightek_people_payout_senders_on_financial_account_ref", unique: true
  end

  create_table "lightek_press_contacts", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "email", null: false
    t.string "outlet", null: false
    t.string "contact_basis", null: false
    t.boolean "suppressed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "email"], name: "index_lightek_press_contacts_on_site_id_and_email", unique: true
  end

  create_table "lightek_pwa_admin_events", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "actor_id", null: false
    t.string "action", null: false
    t.string "record_type"
    t.bigint "record_id"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_pwa_admin_events_on_actor_id"
    t.index ["site_id"], name: "index_lightek_pwa_admin_events_on_site_id"
  end

  create_table "lightek_pwa_applications", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name"
    t.string "short_name"
    t.text "description"
    t.string "theme_color", default: "#c9a34b", null: false
    t.string "background_color", default: "#07070a", null: false
    t.string "status", default: "published", null: false
    t.string "start_surface", default: "home", null: false
    t.string "support_email"
    t.text "welcome_message"
    t.jsonb "settings", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_lightek_pwa_applications_on_site_id", unique: true
  end

  create_table "lightek_pwa_creator_earnings", force: :cascade do |t|
    t.bigint "creator_payment_id", null: false
    t.bigint "order_id", null: false
    t.integer "principal_cents", null: false
    t.string "state", default: "held", null: false
    t.string "charge_reference"
    t.string "transfer_reference"
    t.string "reversal_reference"
    t.string "destination_account"
    t.datetime "available_at"
    t.string "hold_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "transfer_requested_at"
    t.index ["charge_reference"], name: "index_lightek_pwa_creator_earnings_on_charge_reference"
    t.index ["creator_payment_id"], name: "index_lightek_pwa_creator_earnings_on_creator_payment_id"
    t.index ["order_id"], name: "index_lightek_pwa_creator_earnings_on_order_id", unique: true
  end

  create_table "lightek_pwa_creator_offers", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "creator_id", null: false
    t.integer "monthly_cents", default: 500, null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_lightek_pwa_creator_offers_on_creator_id"
    t.index ["site_id", "creator_id"], name: "pwa_creator_offer_identity", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_creator_offers_on_site_id"
  end

  create_table "lightek_pwa_creator_payments", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "creator_id", null: false
    t.bigint "supporter_id", null: false
    t.bigint "order_id", null: false
    t.bigint "post_id"
    t.string "kind", null: false
    t.string "request_key", null: false
    t.integer "principal_cents", null: false
    t.integer "fee_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_lightek_pwa_creator_payments_on_creator_id"
    t.index ["order_id"], name: "index_lightek_pwa_creator_payments_on_order_id", unique: true
    t.index ["post_id"], name: "index_lightek_pwa_creator_payments_on_post_id"
    t.index ["site_id", "supporter_id", "request_key"], name: "pwa_support_payment_identity", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_creator_payments_on_site_id"
    t.index ["supporter_id"], name: "index_lightek_pwa_creator_payments_on_supporter_id"
  end

  create_table "lightek_pwa_launch_settings", force: :cascade do |t|
    t.json "settings", default: {}, null: false
    t.bigint "updated_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["updated_by_id"], name: "index_lightek_pwa_launch_settings_on_updated_by_id"
  end

  create_table "lightek_pwa_member_backends", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.bigint "shared_pool_id"
    t.bigint "launch_id"
    t.bigint "order_id"
    t.string "public_key", null: false
    t.string "hostname", null: false
    t.string "status", default: "queued", null: false
    t.string "error_code"
    t.jsonb "migration_receipt", default: {}, null: false
    t.bigint "copied_bytes", default: 0, null: false
    t.datetime "retire_after"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hosting_mode", default: "shared_account", null: false
    t.jsonb "account_receipt", default: {}, null: false
    t.index ["hostname"], name: "index_lightek_pwa_member_backends_on_hostname", unique: true
    t.index ["launch_id"], name: "index_lightek_pwa_member_backends_on_launch_id"
    t.index ["order_id"], name: "index_lightek_pwa_member_backends_on_order_id"
    t.index ["public_key"], name: "index_lightek_pwa_member_backends_on_public_key", unique: true
    t.index ["shared_pool_id"], name: "index_lightek_pwa_member_backends_on_shared_pool_id"
    t.index ["site_id", "user_id"], name: "pwa_member_backend_identity", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_member_backends_on_site_id"
    t.index ["user_id"], name: "index_lightek_pwa_member_backends_on_user_id"
  end

  create_table "lightek_pwa_member_signup_requests", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.string "state", default: "queued", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "user_id"], name: "pwa_signup_backend_request", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_member_signup_requests_on_site_id"
    t.index ["user_id"], name: "index_lightek_pwa_member_signup_requests_on_user_id"
  end

  create_table "lightek_pwa_member_tickets", force: :cascade do |t|
    t.bigint "member_backend_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "redeemed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_backend_id"], name: "index_lightek_pwa_member_tickets_on_member_backend_id"
    t.index ["token_digest"], name: "index_lightek_pwa_member_tickets_on_token_digest", unique: true
  end

  create_table "lightek_pwa_memberships", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "profile_id", null: false
    t.string "role", default: "member", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_lightek_pwa_memberships_on_profile_id"
    t.index ["site_id", "profile_id"], name: "idx_pwa_site_profile", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_memberships_on_site_id"
  end

  create_table "lightek_pwa_navigation_items", force: :cascade do |t|
    t.string "key", null: false
    t.string "label", null: false
    t.string "surface_key"
    t.string "href"
    t.string "placement", default: "primary", null: false
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.string "requires_capability"
    t.jsonb "configuration", default: {}, null: false
    t.string "seed_namespace"
    t.integer "seed_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_lightek_pwa_navigation_items_on_key", unique: true
  end

  create_table "lightek_pwa_platform_operators", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "operator_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id"], name: "index_lightek_pwa_platform_operators_on_operator_id"
    t.index ["site_id"], name: "index_lightek_pwa_platform_operators_on_site_id", unique: true
  end

  create_table "lightek_pwa_publication_outboxes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "remote_post_id", null: false
    t.bigint "revision", default: 0, null: false
    t.bigint "delivered_revision", default: 0, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "remote_post_id"], name: "pwa_outbox_post_unique", unique: true
  end

  create_table "lightek_pwa_publication_references", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "remote_post_id", null: false
    t.bigint "post_id"
    t.bigint "revision", default: 0, null: false
    t.boolean "removed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["peer_id", "remote_post_id"], name: "pwa_remote_post_unique", unique: true
    t.index ["post_id"], name: "index_lightek_pwa_publication_references_on_post_id"
  end

  create_table "lightek_pwa_purchases", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "site_id", null: false
    t.bigint "order_id", null: false
    t.string "plan_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_lightek_pwa_purchases_on_order_id", unique: true
    t.index ["site_id", "user_id"], name: "index_lightek_pwa_purchases_on_site_id_and_user_id"
    t.index ["user_id"], name: "index_lightek_pwa_purchases_on_user_id"
  end

  create_table "lightek_pwa_revenue_periods", force: :cascade do |t|
    t.bigint "purchase_id", null: false
    t.string "source_reference", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.integer "creator_share_bps", default: 8000, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purchase_id", "starts_at", "ends_at"], name: "pwa_paid_revenue_window"
    t.index ["source_reference"], name: "index_lightek_pwa_revenue_periods_on_source_reference", unique: true
  end

  create_table "lightek_pwa_shared_pools", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "operator_id", null: false
    t.bigint "launch_id"
    t.bigint "node_id"
    t.string "request_key", null: false
    t.string "name", null: false
    t.string "status", default: "provisioning", null: false
    t.integer "max_members", default: 4, null: false
    t.bigint "member_storage_bytes", default: 536870912, null: false
    t.integer "monthly_cost_ceiling_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "capacity_alert_state", default: "normal", null: false
    t.bigint "standby_launch_id"
    t.index ["launch_id"], name: "index_lightek_pwa_shared_pools_on_launch_id"
    t.index ["node_id"], name: "index_lightek_pwa_shared_pools_on_node_id"
    t.index ["operator_id"], name: "index_lightek_pwa_shared_pools_on_operator_id"
    t.index ["request_key"], name: "index_lightek_pwa_shared_pools_on_request_key", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_shared_pools_on_site_id"
    t.index ["standby_launch_id"], name: "index_lightek_pwa_shared_pools_on_standby_launch_id"
  end

  create_table "lightek_pwa_surface_modules", force: :cascade do |t|
    t.bigint "surface_id", null: false
    t.string "key", null: false
    t.string "module_type", null: false
    t.string "label"
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.string "data_source"
    t.string "capability"
    t.jsonb "configuration", default: {}, null: false
    t.string "seed_namespace"
    t.integer "seed_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["surface_id", "key"], name: "idx_lightek_surface_modules_unique", unique: true
    t.index ["surface_id"], name: "index_lightek_pwa_surface_modules_on_surface_id"
  end

  create_table "lightek_pwa_surfaces", force: :cascade do |t|
    t.string "key", null: false
    t.string "surface_type", null: false
    t.string "label", null: false
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "configuration", default: {}, null: false
    t.string "seed_namespace"
    t.integer "seed_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_lightek_pwa_surfaces_on_key", unique: true
  end

  create_table "lightek_pwa_view_batches", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "recorded_by_id", null: false
    t.string "channel_id", null: false
    t.date "month", null: false
    t.string "currency", default: "usd", null: false
    t.bigint "finalized_cents", null: false
    t.bigint "estimated_micros", null: false
    t.bigint "creator_liability_cents", null: false
    t.string "source_reference", null: false
    t.string "report_sha256", null: false
    t.string "finalized_receipt_sha256", null: false
    t.string "state", default: "reconciled", null: false
    t.string "funding_reference"
    t.string "funding_balance_transaction"
    t.string "platform_account"
    t.bigint "funded_cents"
    t.datetime "funded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "month"], name: "pwa_channel_finalized_month", unique: true
    t.index ["funding_reference"], name: "index_lightek_pwa_view_batches_on_funding_reference", unique: true
    t.index ["recorded_by_id"], name: "index_lightek_pwa_view_batches_on_recorded_by_id"
    t.index ["site_id"], name: "index_lightek_pwa_view_batches_on_site_id"
  end

  create_table "lightek_pwa_view_earnings", force: :cascade do |t|
    t.bigint "view_batch_id", null: false
    t.bigint "user_id", null: false
    t.string "video_id", null: false
    t.bigint "views", null: false
    t.bigint "amount_cents", null: false
    t.string "state", default: "awaiting_funding", null: false
    t.string "destination_account"
    t.string "transfer_reference"
    t.string "transfer_key", null: false
    t.datetime "transfer_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["transfer_key"], name: "index_lightek_pwa_view_earnings_on_transfer_key", unique: true
    t.index ["transfer_reference"], name: "index_lightek_pwa_view_earnings_on_transfer_reference", unique: true
    t.index ["user_id"], name: "index_lightek_pwa_view_earnings_on_user_id"
    t.index ["view_batch_id", "user_id", "video_id"], name: "pwa_finalized_creator_video", unique: true
    t.index ["view_batch_id"], name: "index_lightek_pwa_view_earnings_on_view_batch_id"
  end

  create_table "lightek_pwa_youtube_revenues", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.bigint "recorded_by_id", null: false
    t.string "video_id", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.string "source_reference", null: false
    t.string "report_sha256", null: false
    t.bigint "views", default: 0, null: false
    t.bigint "amount_cents", null: false
    t.integer "creator_share_bps", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_by_id"], name: "index_lightek_pwa_youtube_revenues_on_recorded_by_id"
    t.index ["site_id", "video_id", "period_start", "period_end"], name: "pwa_youtube_period_unique", unique: true
    t.index ["user_id"], name: "index_lightek_pwa_youtube_revenues_on_user_id"
  end

  create_table "lightek_pwa_youtube_uploads", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.bigint "post_id"
    t.bigint "peer_id"
    t.string "public_key", null: false
    t.bigint "source_post_id"
    t.bigint "source_blob_id"
    t.string "source_grant", limit: 4096
    t.string "central_key"
    t.string "status", default: "queued", null: false
    t.string "title", null: false
    t.text "description"
    t.boolean "made_for_kids", null: false
    t.integer "byte_size", null: false
    t.string "checksum", null: false
    t.string "content_type", null: false
    t.string "video_id"
    t.string "error_code"
    t.datetime "session_started_at"
    t.datetime "withdraw_requested_at"
    t.datetime "consented_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["peer_id", "source_post_id"], name: "pwa_peer_youtube_source", unique: true
    t.index ["peer_id"], name: "index_lightek_pwa_youtube_uploads_on_peer_id"
    t.index ["post_id"], name: "index_lightek_pwa_youtube_uploads_on_post_id", unique: true
    t.index ["public_key"], name: "index_lightek_pwa_youtube_uploads_on_public_key", unique: true
    t.index ["site_id"], name: "index_lightek_pwa_youtube_uploads_on_site_id"
    t.index ["user_id"], name: "index_lightek_pwa_youtube_uploads_on_user_id"
  end

  create_table "lightek_reservation_blackouts", force: :cascade do |t|
    t.bigint "resource_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_id"], name: "index_lightek_reservation_blackouts_on_resource_id"
  end

  create_table "lightek_reservation_changes", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.bigint "target_resource_id", null: false
    t.bigint "order_id"
    t.string "status", default: "quoted", null: false
    t.integer "amount_cents", null: false
    t.datetime "effective_at", null: false
    t.datetime "expires_at", null: false
    t.jsonb "quote", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "provider_receipt", default: {}, null: false
    t.index ["order_id"], name: "idx_reservation_changes_unique_order", unique: true, where: "(order_id IS NOT NULL)"
    t.index ["order_id"], name: "index_lightek_reservation_changes_on_order_id"
    t.index ["reservation_id"], name: "index_lightek_reservation_changes_on_reservation_id"
    t.index ["target_resource_id"], name: "index_lightek_reservation_changes_on_target_resource_id"
  end

  create_table "lightek_reservation_intents", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "resource_id", null: false
    t.bigint "reservation_id"
    t.bigint "customer_id"
    t.string "token", null: false
    t.string "checkout_key", null: false
    t.string "remote_subject", null: false
    t.datetime "starts_at", null: false
    t.datetime "expires_at", null: false
    t.integer "price_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_lightek_reservation_intents_on_customer_id"
    t.index ["peer_id", "checkout_key"], name: "idx_reservation_peer_checkout", unique: true
    t.index ["peer_id"], name: "index_lightek_reservation_intents_on_peer_id"
    t.index ["reservation_id"], name: "index_lightek_reservation_intents_on_reservation_id"
    t.index ["resource_id"], name: "index_lightek_reservation_intents_on_resource_id"
    t.index ["token"], name: "index_lightek_reservation_intents_on_token", unique: true
  end

  create_table "lightek_reservation_peers", force: :cascade do |t|
    t.string "key", null: false
    t.string "token_digest", null: false
    t.bigint "order_id"
    t.bigint "merchant_id", null: false
    t.bigint "site_id", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "member_backend_id"
    t.index ["key"], name: "index_lightek_reservation_peers_on_key", unique: true
    t.index ["member_backend_id"], name: "index_lightek_reservation_peers_on_member_backend_id", unique: true
    t.index ["merchant_id"], name: "index_lightek_reservation_peers_on_merchant_id"
    t.index ["order_id"], name: "index_lightek_reservation_peers_on_order_id", unique: true
    t.index ["site_id"], name: "index_lightek_reservation_peers_on_site_id", unique: true
  end

  create_table "lightek_reservation_resources", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "source_resource_id"
    t.bigint "product_id"
    t.string "name", null: false
    t.text "description"
    t.string "kind", default: "service", null: false
    t.string "timezone", default: "America/New_York", null: false
    t.integer "capacity", default: 1, null: false
    t.integer "duration_minutes", default: 60, null: false
    t.integer "buffer_minutes", default: 0, null: false
    t.integer "notice_minutes", default: 60, null: false
    t.integer "cancellation_hours", default: 24, null: false
    t.boolean "published", default: false, null: false
    t.jsonb "hours", default: {}, null: false
    t.string "location"
    t.string "join_url"
    t.string "template_key"
    t.string "billing_interval", default: "monthly", null: false
    t.jsonb "accommodations", default: [], null: false
    t.jsonb "compute", default: {}, null: false
    t.integer "cost_floor_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_lightek_reservation_resources_on_product_id"
    t.index ["site_id"], name: "index_lightek_reservation_resources_on_site_id"
  end

  create_table "lightek_reservations", force: :cascade do |t|
    t.bigint "resource_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "order_id"
    t.string "reference", null: false
    t.string "checkout_key", null: false
    t.string "status", default: "held", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "blocks_from", null: false
    t.datetime "blocks_until", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "hold_until"
    t.datetime "canceled_at"
    t.text "notes"
    t.jsonb "notification_keys", default: [], null: false
    t.jsonb "package_snapshot", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "checkout_key"], name: "index_lightek_reservations_on_customer_id_and_checkout_key", unique: true
    t.index ["customer_id"], name: "index_lightek_reservations_on_customer_id"
    t.index ["order_id"], name: "idx_reservations_unique_order", unique: true, where: "(order_id IS NOT NULL)"
    t.index ["order_id"], name: "index_lightek_reservations_on_order_id"
    t.index ["reference"], name: "index_lightek_reservations_on_reference", unique: true
    t.index ["resource_id", "blocks_from", "blocks_until"], name: "idx_reservations_availability"
    t.index ["resource_id"], name: "index_lightek_reservations_on_resource_id"
  end

  create_table "lightek_sales_accounts", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "owner_id"
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "website"
    t.text "notes"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_lightek_sales_accounts_on_owner_id"
    t.index ["site_id", "normalized_name"], name: "idx_sales_account_name", unique: true
    t.index ["site_id"], name: "index_lightek_sales_accounts_on_site_id"
  end

  create_table "lightek_sales_activities", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "actor_id", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.string "kind", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_lightek_sales_activities_on_actor_id"
    t.index ["site_id", "record_type", "record_id", "created_at"], name: "idx_sales_activity_timeline"
    t.index ["site_id"], name: "index_lightek_sales_activities_on_site_id"
  end

  create_table "lightek_sales_commission_payouts", force: :cascade do |t|
    t.bigint "referral_id", null: false
    t.bigint "order_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "released_by_id"
    t.bigint "amount_cents", null: false
    t.string "sender_ref", null: false
    t.string "recipient_ref", null: false
    t.boolean "live", null: false
    t.string "provider_ref"
    t.string "state", default: "preparing", null: false
    t.bigint "review_debit_cents"
    t.string "review_digest"
    t.datetime "release_attempted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_lightek_sales_commission_payouts_on_order_id", unique: true
    t.index ["owner_id"], name: "index_lightek_sales_commission_payouts_on_owner_id"
    t.index ["provider_ref"], name: "index_lightek_sales_commission_payouts_on_provider_ref", unique: true
    t.index ["referral_id"], name: "index_lightek_sales_commission_payouts_on_referral_id", unique: true
    t.index ["released_by_id"], name: "index_lightek_sales_commission_payouts_on_released_by_id"
    t.check_constraint "amount_cents > 0", name: "sales_commission_payout_positive"
  end

  create_table "lightek_sales_intake_entries", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "inquiry_id"
    t.bigint "lead_id"
    t.bigint "created_by_id", null: false
    t.bigint "processed_by_id"
    t.string "origin", null: false
    t.string "origin_key", null: false
    t.string "source", null: false
    t.string "status", default: "awaiting_review", null: false
    t.jsonb "payload", default: {}, null: false
    t.jsonb "original", default: {}, null: false
    t.string "error_message"
    t.datetime "processed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_lightek_sales_intake_entries_on_created_by_id"
    t.index ["inquiry_id"], name: "index_lightek_sales_intake_entries_on_inquiry_id"
    t.index ["lead_id"], name: "index_lightek_sales_intake_entries_on_lead_id"
    t.index ["processed_by_id"], name: "index_lightek_sales_intake_entries_on_processed_by_id"
    t.index ["site_id", "origin_key"], name: "idx_sales_intake_origin", unique: true
    t.index ["site_id", "status", "created_at"], name: "idx_sales_intake_review"
    t.index ["site_id"], name: "index_lightek_sales_intake_entries_on_site_id"
  end

  create_table "lightek_sales_intake_rules", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "template_key", null: false
    t.string "section_key", null: false
    t.string "source", default: "website", null: false
    t.jsonb "mapping", default: {}, null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "enabled_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "template_key", "section_key"], name: "idx_sales_intake_form", unique: true
    t.index ["site_id"], name: "index_lightek_sales_intake_rules_on_site_id"
  end

  create_table "lightek_sales_leads", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "owner_id"
    t.bigint "opportunity_id"
    t.string "name", null: false
    t.string "email", null: false
    t.string "company", null: false
    t.string "phone"
    t.string "source", default: "manual", null: false
    t.string "status", default: "new", null: false
    t.string "next_step"
    t.date "follow_up_on"
    t.text "notes"
    t.datetime "converted_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "growth_visit_id"
    t.index ["growth_visit_id"], name: "index_lightek_sales_leads_on_growth_visit_id"
    t.index ["opportunity_id"], name: "index_lightek_sales_leads_on_opportunity_id"
    t.index ["owner_id"], name: "index_lightek_sales_leads_on_owner_id"
    t.index ["site_id", "email"], name: "index_lightek_sales_leads_on_site_id_and_email", unique: true
    t.index ["site_id", "status", "follow_up_on"], name: "idx_sales_lead_follow_up"
    t.index ["site_id"], name: "index_lightek_sales_leads_on_site_id"
  end

  create_table "lightek_sales_opportunities", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "owner_id"
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.string "name", null: false
    t.string "stage", default: "discovery", null: false
    t.string "forecast_category", default: "pipeline", null: false
    t.bigint "amount_cents", default: 0, null: false
    t.string "currency", default: "USD", null: false
    t.integer "probability", default: 10, null: false
    t.date "close_on", null: false
    t.string "next_step"
    t.date "follow_up_on"
    t.text "notes"
    t.string "loss_reason"
    t.datetime "stage_changed_at"
    t.datetime "closed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "growth_visit_id"
    t.index ["account_id"], name: "index_lightek_sales_opportunities_on_account_id"
    t.index ["contact_id"], name: "index_lightek_sales_opportunities_on_contact_id"
    t.index ["growth_visit_id"], name: "index_lightek_sales_opportunities_on_growth_visit_id"
    t.index ["owner_id"], name: "index_lightek_sales_opportunities_on_owner_id"
    t.index ["site_id", "stage", "close_on"], name: "idx_sales_pipeline"
    t.index ["site_id"], name: "index_lightek_sales_opportunities_on_site_id"
    t.check_constraint "amount_cents >= 0 AND probability >= 0 AND probability <= 100", name: "sales_opportunity_amount_probability"
  end

  create_table "lightek_sales_partners", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.string "agreement_reference", null: false
    t.bigint "commission_cents", null: false
    t.string "referral_code", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "payout_email"
    t.string "payout_recipient_ref"
    t.string "payout_sender_ref"
    t.boolean "payout_live"
    t.bigint "payout_user_id"
    t.bigint "payout_invited_by_id"
    t.string "payout_entity_type"
    t.datetime "payout_setup_started_at"
    t.index ["payout_invited_by_id"], name: "index_lightek_sales_partners_on_payout_invited_by_id"
    t.index ["payout_user_id"], name: "index_lightek_sales_partners_on_payout_user_id"
    t.index ["product_id"], name: "index_lightek_sales_partners_on_product_id"
    t.index ["referral_code"], name: "index_lightek_sales_partners_on_referral_code", unique: true
    t.index ["site_id"], name: "index_lightek_sales_partners_on_site_id"
    t.check_constraint "commission_cents > 0", name: "sales_partner_positive_commission"
  end

  create_table "lightek_sales_prospecting_cadences", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.json "steps", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "name"], name: "idx_sales_prospecting_cadence_name", unique: true
    t.index ["site_id"], name: "index_lightek_sales_prospecting_cadences_on_site_id"
  end

  create_table "lightek_sales_quotes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "opportunity_id", null: false
    t.bigint "accepted_by_id"
    t.string "acceptance_channel"
    t.bigint "created_by_id", null: false
    t.bigint "order_id"
    t.string "series_key", null: false
    t.integer "revision", default: 1, null: false
    t.string "status", default: "draft", null: false
    t.string "portal_host", null: false
    t.string "customer_email", null: false
    t.string "title", null: false
    t.string "currency", default: "USD", null: false
    t.bigint "total_cents", default: 0, null: false
    t.jsonb "lines", default: [], null: false
    t.text "terms"
    t.date "expires_on", null: false
    t.datetime "issued_at"
    t.datetime "accepted_at"
    t.string "accepted_name"
    t.string "acceptance_reference"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_id"], name: "index_lightek_sales_quotes_on_accepted_by_id"
    t.index ["created_by_id"], name: "index_lightek_sales_quotes_on_created_by_id"
    t.index ["opportunity_id"], name: "index_lightek_sales_quotes_on_opportunity_id"
    t.index ["order_id"], name: "index_lightek_sales_quotes_on_order_id", unique: true
    t.index ["site_id", "series_key", "revision"], name: "idx_sales_quote_revision", unique: true
    t.index ["site_id"], name: "index_lightek_sales_quotes_on_site_id"
  end

  create_table "lightek_sales_referrals", force: :cascade do |t|
    t.bigint "partner_id", null: false
    t.bigint "lead_id", null: false
    t.bigint "commission_cents", null: false
    t.bigint "order_id"
    t.bigint "recorded_by_id"
    t.string "payout_reference"
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_lightek_sales_referrals_on_lead_id", unique: true
    t.index ["order_id"], name: "index_lightek_sales_referrals_on_order_id", unique: true
    t.index ["partner_id"], name: "index_lightek_sales_referrals_on_partner_id"
    t.index ["payout_reference"], name: "index_lightek_sales_referrals_on_payout_reference", unique: true
    t.index ["recorded_by_id"], name: "index_lightek_sales_referrals_on_recorded_by_id"
    t.check_constraint "commission_cents > 0", name: "sales_referral_positive_commission"
  end

  create_table "lightek_sales_routing_rules", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "owner_id", null: false
    t.string "source", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_lightek_sales_routing_rules_on_owner_id"
    t.index ["site_id", "source"], name: "index_lightek_sales_routing_rules_on_site_id_and_source", unique: true
    t.index ["site_id"], name: "index_lightek_sales_routing_rules_on_site_id"
  end

  create_table "lightek_sales_social_prospects", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "lead_id"
    t.bigint "saved_by_id", null: false
    t.bigint "contacted_by_id"
    t.string "provider", null: false
    t.string "remote_id"
    t.string "source_post_id"
    t.string "sender_id"
    t.string "outreach_status", default: "ready", null: false
    t.string "provider_message_id"
    t.string "contact_permission"
    t.datetime "contacted_at"
    t.datetime "contact_blocked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "web_username"
    t.string "web_profile_url"
    t.string "web_source_url"
    t.string "web_display_name"
    t.string "business_website_url"
    t.text "website_finding"
    t.index ["contacted_by_id"], name: "index_lightek_sales_social_prospects_on_contacted_by_id"
    t.index ["lead_id"], name: "index_lightek_sales_social_prospects_on_lead_id"
    t.index ["saved_by_id"], name: "index_lightek_sales_social_prospects_on_saved_by_id"
    t.index ["site_id", "provider", "remote_id"], name: "idx_lightek_sales_social_prospect_identity", unique: true
    t.index ["site_id", "provider", "web_profile_url"], name: "idx_sales_prospect_web_profile", unique: true, where: "(web_profile_url IS NOT NULL)"
    t.index ["site_id", "provider", "web_username"], name: "idx_lightek_sales_social_prospect_web_identity", unique: true, where: "(web_username IS NOT NULL)"
    t.index ["site_id"], name: "index_lightek_sales_social_prospects_on_site_id"
  end

  create_table "lightek_sales_tasks", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "created_by_id", null: false
    t.bigint "completed_by_id"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.string "source_key", null: false
    t.string "title", null: false
    t.string "status", default: "open", null: false
    t.datetime "due_at", null: false
    t.datetime "completed_at"
    t.datetime "snoozed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["completed_by_id"], name: "index_lightek_sales_tasks_on_completed_by_id"
    t.index ["created_by_id"], name: "index_lightek_sales_tasks_on_created_by_id"
    t.index ["owner_id"], name: "index_lightek_sales_tasks_on_owner_id"
    t.index ["record_type", "record_id"], name: "idx_sales_task_relationship"
    t.index ["site_id", "owner_id", "status", "due_at"], name: "idx_sales_tasks_due"
    t.index ["site_id", "source_key"], name: "idx_sales_task_source", unique: true
    t.index ["site_id"], name: "index_lightek_sales_tasks_on_site_id"
  end

  create_table "lightek_session_members", force: :cascade do |t|
    t.bigint "room_id", null: false
    t.bigint "user_id", null: false
    t.bigint "reservation_id"
    t.string "status", default: "waiting", null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reservation_id"], name: "index_lightek_session_members_on_reservation_id"
    t.index ["room_id", "user_id"], name: "index_lightek_session_members_on_room_id_and_user_id", unique: true
    t.index ["room_id"], name: "index_lightek_session_members_on_room_id"
    t.index ["user_id"], name: "index_lightek_session_members_on_user_id"
  end

  create_table "lightek_session_rooms", force: :cascade do |t|
    t.bigint "resource_id", null: false
    t.string "key", null: false
    t.string "media_name", null: false
    t.jsonb "retired_media_names", default: [], null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "scheduled", null: false
    t.boolean "locked", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "presentation", default: {}, null: false
    t.string "purpose", default: "booking", null: false
    t.bigint "host_user_id"
    t.index ["host_user_id"], name: "index_lightek_session_rooms_on_host_user_id"
    t.index ["key"], name: "index_lightek_session_rooms_on_key", unique: true
    t.index ["resource_id", "starts_at", "ends_at"], name: "idx_lightek_room_slot", unique: true
    t.index ["resource_id"], name: "index_lightek_session_rooms_on_resource_id"
    t.check_constraint "(purpose::text = ANY (ARRAY['booking'::character varying, 'production'::character varying]::text[])) AND (purpose::text <> 'production'::text OR host_user_id IS NOT NULL)", name: "session_room_purpose_valid"
  end

  create_table "lightek_shared_calendars", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", limit: 120, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employer_id"], name: "index_lightek_shared_calendars_on_employer_id"
  end

  create_table "lightek_shared_drive_entries", force: :cascade do |t|
    t.bigint "drive_id", null: false
    t.bigint "parent_id"
    t.bigint "creator_id", null: false
    t.string "name", limit: 160, null: false
    t.boolean "folder", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_lightek_shared_drive_entries_on_creator_id"
    t.index ["drive_id", "parent_id"], name: "index_lightek_shared_drive_entries_on_drive_id_and_parent_id"
    t.index ["drive_id"], name: "index_lightek_shared_drive_entries_on_drive_id"
    t.index ["parent_id"], name: "index_lightek_shared_drive_entries_on_parent_id"
  end

  create_table "lightek_shared_drive_import_receipts", force: :cascade do |t|
    t.bigint "drive_id", null: false
    t.bigint "entry_id"
    t.string "source_key", limit: 64, null: false
    t.string "digest", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["drive_id", "source_key"], name: "idx_drive_import_receipt_source", unique: true
    t.index ["drive_id"], name: "index_lightek_shared_drive_import_receipts_on_drive_id"
    t.index ["entry_id"], name: "index_lightek_shared_drive_import_receipts_on_entry_id"
  end

  create_table "lightek_shared_drive_imports", force: :cascade do |t|
    t.bigint "drive_id", null: false
    t.bigint "folder_id"
    t.bigint "actor_id", null: false
    t.string "filename", null: false
    t.string "state", default: "preview", null: false
    t.string "run_token"
    t.jsonb "items", default: [], null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "team_migration_id"
    t.index ["actor_id"], name: "index_lightek_shared_drive_imports_on_actor_id"
    t.index ["drive_id"], name: "index_lightek_shared_drive_imports_on_drive_id"
    t.index ["folder_id"], name: "index_lightek_shared_drive_imports_on_folder_id"
    t.index ["team_migration_id"], name: "index_lightek_shared_drive_imports_on_team_migration_id"
  end

  create_table "lightek_shared_drive_members", force: :cascade do |t|
    t.bigint "drive_id", null: false
    t.bigint "user_id", null: false
    t.string "role", null: false
    t.index ["drive_id", "user_id"], name: "index_lightek_shared_drive_members_on_drive_id_and_user_id", unique: true
    t.index ["drive_id"], name: "index_lightek_shared_drive_members_on_drive_id"
    t.index ["user_id"], name: "index_lightek_shared_drive_members_on_user_id"
  end

  create_table "lightek_shared_drives", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", limit: 120, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "revision_retention_days"
    t.index ["employer_id"], name: "index_lightek_shared_drives_on_employer_id"
    t.check_constraint "revision_retention_days >= 1 AND revision_retention_days <= 36500", name: "shared_drive_revision_retention_days"
  end

  create_table "lightek_shared_event_guests", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "user_id", null: false
    t.string "response", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "user_id"], name: "index_lightek_shared_event_guests_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_lightek_shared_event_guests_on_event_id"
    t.index ["user_id"], name: "index_lightek_shared_event_guests_on_user_id"
  end

  create_table "lightek_shared_events", force: :cascade do |t|
    t.bigint "calendar_id", null: false
    t.bigint "organizer_id", null: false
    t.string "title", limit: 160, null: false
    t.text "details"
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "series_key", limit: 36
    t.bigint "session_room_id"
    t.index ["calendar_id", "series_key", "starts_at"], name: "index_shared_events_on_series_and_start", where: "(series_key IS NOT NULL)"
    t.index ["calendar_id", "starts_at"], name: "index_lightek_shared_events_on_calendar_id_and_starts_at"
    t.index ["calendar_id"], name: "index_lightek_shared_events_on_calendar_id"
    t.index ["organizer_id"], name: "index_lightek_shared_events_on_organizer_id"
    t.index ["session_room_id"], name: "index_lightek_shared_events_on_session_room_id", unique: true
    t.check_constraint "ends_at > starts_at", name: "shared_event_positive_duration"
  end

  create_table "lightek_shared_external_invitations", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "mailbox_id", null: false
    t.bigint "message_id"
    t.string "organizer_address", limit: 254, null: false
    t.string "attendee_address", limit: 254, null: false
    t.string "uid", null: false
    t.integer "sequence", default: 0, null: false
    t.string "response", default: "pending", null: false
    t.datetime "reply_timestamp"
    t.string "delivery_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "attendee_address"], name: "idx_on_event_id_attendee_address_f1b75f2f68", unique: true
    t.index ["mailbox_id"], name: "index_lightek_shared_external_invitations_on_mailbox_id"
    t.index ["message_id"], name: "index_lightek_shared_external_invitations_on_message_id"
    t.index ["uid"], name: "index_lightek_shared_external_invitations_on_uid", unique: true
  end

  create_table "lightek_shipping_accounts", force: :cascade do |t|
    t.string "provider", default: "fedex", null: false
    t.string "credential_slug", null: false
    t.boolean "sandbox", default: true, null: false
    t.boolean "enabled", default: false, null: false
    t.boolean "production_approved", default: false, null: false
    t.integer "markup_bps", default: 0, null: false
    t.integer "fixed_markup_cents", default: 0, null: false
    t.integer "minimum_margin_cents", default: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider"], name: "index_lightek_shipping_accounts_on_provider", unique: true
  end

  create_table "lightek_shipping_profiles", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.jsonb "origin", default: {}, null: false
    t.jsonb "default_package", default: {}, null: false
    t.integer "customer_markup_bps", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_lightek_shipping_profiles_on_site_id", unique: true
  end

  create_table "lightek_shipping_quotes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "public_key", null: false
    t.string "broker_reference"
    t.string "service_code", null: false
    t.string "service_name", null: false
    t.string "currency", default: "usd", null: false
    t.integer "carrier_cost_cents"
    t.integer "platform_price_cents", null: false
    t.integer "customer_price_cents", null: false
    t.boolean "sandbox", default: true, null: false
    t.jsonb "shipment_payload", default: {}, null: false
    t.string "cart_fingerprint"
    t.datetime "expires_at", null: false
    t.bigint "purchase_order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["broker_reference"], name: "index_lightek_shipping_quotes_on_broker_reference"
    t.index ["public_key"], name: "index_lightek_shipping_quotes_on_public_key", unique: true
    t.index ["purchase_order_id"], name: "index_lightek_shipping_quotes_on_purchase_order_id", unique: true
    t.index ["site_id"], name: "index_lightek_shipping_quotes_on_site_id"
    t.check_constraint "platform_price_cents > 0 AND customer_price_cents >= platform_price_cents AND (carrier_cost_cents IS NULL OR platform_price_cents > carrier_cost_cents)", name: "shipping_retail_price_valid"
  end

  create_table "lightek_shipping_shipments", force: :cascade do |t|
    t.bigint "quote_id", null: false
    t.string "public_key", null: false
    t.string "status", default: "queued", null: false
    t.string "tracking_number"
    t.string "carrier_status"
    t.datetime "submitted_at"
    t.datetime "completed_at"
    t.integer "actual_carrier_cost_cents"
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_key"], name: "index_lightek_shipping_shipments_on_public_key", unique: true
    t.index ["quote_id"], name: "index_lightek_shipping_shipments_on_quote_id", unique: true
  end

  create_table "lightek_social_blocks", force: :cascade do |t|
    t.bigint "blocker_profile_id", null: false
    t.bigint "blocked_profile_id", null: false
    t.string "reason_code"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_profile_id"], name: "index_lightek_social_blocks_on_blocked_profile_id"
    t.index ["blocker_profile_id", "blocked_profile_id"], name: "idx_lightek_social_blocks_pair", unique: true
    t.check_constraint "blocker_profile_id <> blocked_profile_id", name: "chk_lightek_social_block_not_self"
  end

  create_table "lightek_social_circle_memberships", force: :cascade do |t|
    t.bigint "circle_id", null: false
    t.bigint "profile_id", null: false
    t.integer "position", default: 0, null: false
    t.text "note"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["circle_id", "profile_id"], name: "idx_lightek_social_circle_members_pair", unique: true
    t.index ["circle_id"], name: "index_lightek_social_circle_memberships_on_circle_id"
    t.index ["profile_id"], name: "index_lightek_social_circle_memberships_on_profile_id"
  end

  create_table "lightek_social_circles", force: :cascade do |t|
    t.bigint "owner_profile_id", null: false
    t.string "name", null: false
    t.string "name_key", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_profile_id", "name_key"], name: "idx_lightek_social_circles_owner_name", unique: true
    t.index ["owner_profile_id"], name: "index_lightek_social_circles_on_owner_profile_id"
  end

  create_table "lightek_social_connection_opportunities", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.bigint "related_profile_id", null: false
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.string "reason_code"
    t.string "context_type"
    t.bigint "context_id"
    t.string "source_key"
    t.datetime "detected_at", null: false
    t.datetime "expires_at"
    t.datetime "acted_at"
    t.datetime "dismissed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["context_type", "context_id"], name: "idx_lightek_social_opportunities_context"
    t.index ["profile_id", "status", "detected_at"], name: "idx_lightek_social_opportunities_profile_state"
    t.index ["related_profile_id", "status"], name: "idx_lightek_social_opportunities_related"
    t.index ["source_key"], name: "index_lightek_social_connection_opportunities_on_source_key", unique: true, where: "(source_key IS NOT NULL)"
    t.check_constraint "profile_id <> related_profile_id", name: "chk_lightek_social_opportunity_not_self"
  end

  create_table "lightek_social_follows", force: :cascade do |t|
    t.bigint "follower_profile_id", null: false
    t.bigint "followed_profile_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["followed_profile_id"], name: "index_lightek_social_follows_on_followed_profile_id"
    t.index ["follower_profile_id", "followed_profile_id"], name: "idx_lightek_social_follows_pair", unique: true
    t.check_constraint "follower_profile_id <> followed_profile_id", name: "chk_lightek_social_follow_not_self"
  end

  create_table "lightek_social_friendships", force: :cascade do |t|
    t.bigint "requester_profile_id", null: false
    t.bigint "addressee_profile_id", null: false
    t.string "pair_key", null: false
    t.string "status", default: "pending", null: false
    t.datetime "responded_at"
    t.datetime "accepted_at"
    t.datetime "ended_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["addressee_profile_id"], name: "index_lightek_social_friendships_on_addressee_profile_id"
    t.index ["pair_key"], name: "index_lightek_social_friendships_on_pair_key", unique: true
    t.index ["requester_profile_id"], name: "index_lightek_social_friendships_on_requester_profile_id"
    t.index ["status"], name: "index_lightek_social_friendships_on_status"
    t.check_constraint "requester_profile_id <> addressee_profile_id", name: "chk_lightek_social_friendship_not_self"
  end

  create_table "lightek_social_relationship_events", force: :cascade do |t|
    t.bigint "actor_profile_id", null: false
    t.bigint "target_profile_id", null: false
    t.string "pair_key", null: false
    t.string "event_type", null: false
    t.boolean "counts_toward_strength", default: true, null: false
    t.string "context_type"
    t.bigint "context_id"
    t.string "source_key"
    t.datetime "occurred_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_profile_id", "occurred_at"], name: "idx_lightek_social_relationship_events_actor"
    t.index ["context_type", "context_id"], name: "idx_lightek_social_relationship_events_context"
    t.index ["pair_key", "occurred_at"], name: "idx_lightek_social_relationship_events_pair_time"
    t.index ["source_key"], name: "index_lightek_social_relationship_events_on_source_key", unique: true, where: "(source_key IS NOT NULL)"
    t.index ["target_profile_id", "occurred_at"], name: "idx_lightek_social_relationship_events_target"
    t.check_constraint "actor_profile_id <> target_profile_id", name: "chk_lightek_social_relationship_event_not_self"
  end

  create_table "lightek_social_relationship_strengths", force: :cascade do |t|
    t.bigint "profile_a_id", null: false
    t.bigint "profile_b_id", null: false
    t.string "pair_key", null: false
    t.decimal "reciprocity", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "continuity", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "context_diversity", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "shared_experience", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "recency", precision: 5, scale: 4, default: "0.0", null: false
    t.decimal "confidence", precision: 5, scale: 4, default: "0.0", null: false
    t.integer "observed_event_count", default: 0, null: false
    t.datetime "first_observed_at"
    t.datetime "last_observed_at"
    t.datetime "computed_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pair_key"], name: "index_lightek_social_relationship_strengths_on_pair_key", unique: true
    t.index ["profile_a_id"], name: "index_lightek_social_relationship_strengths_on_profile_a_id"
    t.index ["profile_b_id"], name: "index_lightek_social_relationship_strengths_on_profile_b_id"
    t.check_constraint "confidence >= 0::numeric AND confidence <= 1::numeric", name: "chk_lightek_social_strength_confidence"
    t.check_constraint "context_diversity >= 0::numeric AND context_diversity <= 1::numeric", name: "chk_lightek_social_strength_context_diversity"
    t.check_constraint "continuity >= 0::numeric AND continuity <= 1::numeric", name: "chk_lightek_social_strength_continuity"
    t.check_constraint "profile_a_id <> profile_b_id", name: "chk_lightek_social_strength_not_self"
    t.check_constraint "recency >= 0::numeric AND recency <= 1::numeric", name: "chk_lightek_social_strength_recency"
    t.check_constraint "reciprocity >= 0::numeric AND reciprocity <= 1::numeric", name: "chk_lightek_social_strength_reciprocity"
    t.check_constraint "shared_experience >= 0::numeric AND shared_experience <= 1::numeric", name: "chk_lightek_social_strength_shared_experience"
  end

  create_table "lightek_social_top_people", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.bigint "person_id", null: false
    t.integer "position", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_lightek_social_top_people_on_person_id"
    t.index ["profile_id", "person_id"], name: "idx_top_people_person", unique: true
    t.index ["profile_id", "position"], name: "idx_top_people_position", unique: true
    t.index ["profile_id"], name: "index_lightek_social_top_people_on_profile_id"
  end

  create_table "lightek_team_channels", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.bigint "creator_id", null: false
    t.string "name", limit: 60, null: false
    t.string "description", limit: 240
    t.boolean "private_channel", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_lightek_team_channels_on_creator_id"
    t.index ["employer_id", "name"], name: "index_lightek_team_channels_on_employer_id_and_name", unique: true
  end

  create_table "lightek_team_mail_migration_mailboxes", force: :cascade do |t|
    t.bigint "migration_id", null: false
    t.bigint "account_id", null: false
    t.bigint "mailbox_user_id", null: false
    t.string "source_address", limit: 254, null: false
    t.string "destination_address", limit: 254, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "contacts_imported_at"
    t.datetime "calendar_imported_at"
    t.jsonb "contacts_import_result", default: {}, null: false
    t.jsonb "calendar_import_result", default: {}, null: false
    t.index ["account_id"], name: "index_lightek_team_mail_migration_mailboxes_on_account_id"
    t.index ["mailbox_user_id"], name: "index_lightek_team_mail_migration_mailboxes_on_mailbox_user_id"
    t.index ["migration_id", "account_id"], name: "idx_team_mail_destination", unique: true
    t.index ["migration_id", "source_address"], name: "idx_team_mail_source", unique: true
  end

  create_table "lightek_team_mail_migrations", force: :cascade do |t|
    t.bigint "employer_id", null: false
    t.string "name", limit: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "pilot", default: false, null: false
    t.datetime "pilot_verified_at"
    t.index ["employer_id"], name: "index_lightek_team_mail_migrations_on_employer_id"
  end

  create_table "lightek_team_memberships", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "user_id"], name: "index_lightek_team_memberships_on_channel_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_lightek_team_memberships_on_user_id"
  end

  create_table "lightek_team_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "author_id", null: false
    t.bigint "reply_to_id"
    t.text "body", null: false
    t.string "request_key", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "organization_id"
    t.index ["author_id"], name: "index_lightek_team_messages_on_author_id"
    t.index ["channel_id", "author_id", "request_key"], name: "index_team_messages_on_request", unique: true
    t.index ["channel_id", "id"], name: "index_lightek_team_messages_on_channel_id_and_id"
    t.index ["organization_id"], name: "index_lightek_team_messages_on_organization_id"
    t.index ["reply_to_id"], name: "index_lightek_team_messages_on_reply_to_id"
  end

  create_table "lightek_team_network_channels", force: :cascade do |t|
    t.bigint "host_peer_id", null: false
    t.bigint "partner_peer_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "accepted_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["host_peer_id"], name: "index_lightek_team_network_channels_on_host_peer_id"
    t.index ["key"], name: "index_lightek_team_network_channels_on_key", unique: true
    t.index ["partner_peer_id"], name: "index_lightek_team_network_channels_on_partner_peer_id"
  end

  create_table "lightek_team_network_members", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "peer_id", null: false
    t.string "subject", null: false
    t.string "display_name", limit: 120, null: false
    t.index ["channel_id", "peer_id", "subject"], name: "index_network_team_members_on_identity", unique: true
    t.index ["peer_id"], name: "index_lightek_team_network_members_on_peer_id"
  end

  create_table "lightek_team_network_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "peer_id", null: false
    t.string "subject", null: false
    t.string "author", null: false
    t.string "request_key", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "id"], name: "index_lightek_team_network_messages_on_channel_id_and_id"
    t.index ["channel_id", "peer_id", "subject", "request_key"], name: "index_network_team_messages_on_identity", unique: true
    t.index ["peer_id"], name: "index_lightek_team_network_messages_on_peer_id"
  end

  create_table "lightek_team_partner_memberships", force: :cascade do |t|
    t.bigint "partnership_id", null: false
    t.bigint "user_id", null: false
    t.index ["partnership_id", "user_id"], name: "index_team_partner_members_on_partnership_and_user", unique: true
    t.index ["user_id"], name: "index_lightek_team_partner_memberships_on_user_id"
  end

  create_table "lightek_team_partnerships", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "partner_id", null: false
    t.datetime "accepted_at"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_lightek_team_partnerships_on_channel_id", unique: true
    t.index ["partner_id"], name: "index_lightek_team_partnerships_on_partner_id"
  end

  create_table "lightek_vault_audit_events", force: :cascade do |t|
    t.bigint "secret_id", null: false
    t.string "action", null: false
    t.string "consumer"
    t.string "purpose"
    t.string "requested_by"
    t.string "gatekeeper_operation_id"
    t.boolean "allowed", default: false, null: false
    t.string "reason"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_lightek_vault_audit_events_on_action"
    t.index ["created_at"], name: "index_lightek_vault_audit_events_on_created_at"
    t.index ["secret_id"], name: "index_lightek_vault_audit_events_on_secret_id"
  end

  create_table "lightek_vault_secrets", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "secret_type", default: "credential", null: false
    t.string "provider"
    t.string "environment", default: "production", null: false
    t.string "purpose"
    t.string "status", default: "active", null: false
    t.text "ciphertext", null: false
    t.text "encrypted_data_key", null: false
    t.string "payload_iv", null: false
    t.string "payload_tag", null: false
    t.string "key_iv", null: false
    t.string "key_tag", null: false
    t.integer "key_version", default: 1, null: false
    t.jsonb "access_policy", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "last_used_at"
    t.datetime "last_rotated_at"
    t.datetime "expires_at"
    t.datetime "disabled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_policy"], name: "index_lightek_vault_secrets_on_access_policy", using: :gin
    t.index ["expires_at"], name: "index_lightek_vault_secrets_on_expires_at"
    t.index ["metadata"], name: "index_lightek_vault_secrets_on_metadata", using: :gin
    t.index ["provider"], name: "index_lightek_vault_secrets_on_provider"
    t.index ["slug"], name: "index_lightek_vault_secrets_on_slug", unique: true
    t.index ["status"], name: "index_lightek_vault_secrets_on_status"
  end

  create_table "lightek_voice_add_ons", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "order_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "setup_secret_slug"
    t.string "fulfillment_status"
    t.string "cellular_request_key", limit: 36
    t.string "cellular_peer_ip"
    t.string "cellular_group_id", limit: 36
    t.index ["cellular_request_key"], name: "index_lightek_voice_add_ons_on_cellular_request_key", unique: true
    t.index ["order_id"], name: "index_lightek_voice_add_ons_on_order_id", unique: true
    t.index ["peer_id"], name: "index_lightek_voice_add_ons_on_peer_id", unique: true
  end

  create_table "lightek_voice_carrier_operations", force: :cascade do |t|
    t.bigint "service_id", null: false
    t.bigint "operator_id"
    t.string "operation", null: false
    t.string "did", null: false
    t.string "state", default: "submitting", null: false
    t.string "carrier_reference"
    t.string "carrier_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["did"], name: "idx_voice_carrier_assigned_did", unique: true, where: "((operation)::text = ANY ((ARRAY['order_number'::character varying, 'port_number'::character varying])::text[]))"
    t.index ["operator_id"], name: "index_lightek_voice_carrier_operations_on_operator_id"
    t.index ["service_id", "operation"], name: "idx_voice_carrier_service_operation", unique: true
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

  create_table "network_events", force: :cascade do |t|
    t.string "name", null: false
    t.string "source"
    t.string "destination"
    t.string "transport"
    t.boolean "enabled", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_network_events_on_enabled"
    t.index ["name"], name: "index_network_events_on_name", unique: true
  end

  create_table "network_managed_devices", force: :cascade do |t|
    t.string "name", null: false
    t.string "device_type", null: false
    t.string "identifier", null: false
    t.string "status", default: "registered", null: false
    t.string "management_protocol"
    t.string "hostname"
    t.string "ip_address"
    t.string "manufacturer"
    t.string "model"
    t.string "os_version"
    t.text "notes"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "enrollment_token_digest"
    t.datetime "enrolled_at"
    t.datetime "last_seen_at"
    t.string "last_heartbeat_ip"
    t.index ["device_type", "status"], name: "index_network_managed_devices_on_device_type_and_status"
    t.index ["enrollment_token_digest"], name: "index_network_managed_devices_on_enrollment_token_digest", unique: true
    t.index ["identifier"], name: "index_network_managed_devices_on_identifier", unique: true
  end

  create_table "network_ports", force: :cascade do |t|
    t.integer "port", null: false
    t.string "protocol", null: false
    t.string "service"
    t.string "host"
    t.boolean "enabled", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_network_ports_on_enabled"
    t.index ["port", "protocol"], name: "index_network_ports_on_port_and_protocol", unique: true
  end

  create_table "nevaeh_agenda_items", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", limit: 160, null: false
    t.string "category", limit: 20, null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.text "notes"
    t.datetime "closed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "starts_at"], name: "index_nevaeh_agenda_on_open_schedule", where: "(closed_at IS NULL)"
    t.check_constraint "ends_at > starts_at", name: "nevaeh_agenda_has_positive_duration"
  end

  create_table "nevaeh_agent_runs", force: :cascade do |t|
    t.bigint "nevaeh_agent_worker_id", null: false
    t.bigint "actor_id", null: false
    t.bigint "nevaeh_os_action_id"
    t.string "request_key", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "task_uuid", null: false
    t.index ["actor_id"], name: "index_nevaeh_agent_runs_on_actor_id"
    t.index ["nevaeh_agent_worker_id", "request_key"], name: "idx_nevaeh_agent_run_request", unique: true
    t.index ["nevaeh_agent_worker_id"], name: "index_nevaeh_agent_runs_on_nevaeh_agent_worker_id"
    t.index ["nevaeh_os_action_id"], name: "index_nevaeh_agent_runs_on_nevaeh_os_action_id"
    t.index ["task_uuid"], name: "index_nevaeh_agent_runs_on_task_uuid", unique: true
  end

  create_table "nevaeh_agent_workers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "nevaeh_os_agent_id", null: false
    t.string "name", null: false
    t.jsonb "command", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "interval_minutes"
    t.datetime "next_run_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["nevaeh_os_agent_id"], name: "index_nevaeh_agent_workers_on_nevaeh_os_agent_id"
    t.index ["user_id"], name: "index_nevaeh_agent_workers_on_user_id"
  end

  create_table "nevaeh_application_adapters", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "package", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "operations", default: {}, null: false
    t.jsonb "documentation", default: {}, null: false
    t.jsonb "verification", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "package"], name: "idx_nevaeh_app_adapter_owner", unique: true
    t.index ["user_id"], name: "index_nevaeh_application_adapters_on_user_id"
  end

  create_table "nevaeh_calendar_invitees", force: :cascade do |t|
    t.bigint "agenda_item_id", null: false
    t.bigint "mailbox_id", null: false
    t.bigint "message_id"
    t.string "recipient", null: false
    t.string "organizer_address", null: false
    t.integer "sequence", default: 0, null: false
    t.integer "agenda_version"
    t.boolean "cancelled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id", "recipient"], name: "index_nevaeh_calendar_invitees_on_agenda_item_id_and_recipient", unique: true
    t.index ["mailbox_id"], name: "index_nevaeh_calendar_invitees_on_mailbox_id"
    t.index ["message_id"], name: "index_nevaeh_calendar_invitees_on_message_id"
  end

  create_table "nevaeh_capabilities", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "domain", null: false
    t.text "description"
    t.string "intent_name", null: false
    t.string "subject_type"
    t.string "handler", null: false
    t.string "queue", default: "default", null: false
    t.integer "priority", default: 5, null: false
    t.string "gatekeeper_capability"
    t.jsonb "intent_patterns", default: [], null: false
    t.jsonb "expected_outcome", default: {}, null: false
    t.jsonb "failure_policy", default: {}, null: false
    t.jsonb "realtime", default: {}, null: false
    t.jsonb "input_adapter", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "knowledge_article_ids", default: [], null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "event_types", default: [], null: false
    t.index ["domain"], name: "index_nevaeh_capabilities_on_domain"
    t.index ["enabled"], name: "index_nevaeh_capabilities_on_enabled"
    t.index ["event_types"], name: "index_nevaeh_capabilities_on_event_types", using: :gin
    t.index ["handler"], name: "index_nevaeh_capabilities_on_handler"
    t.index ["intent_name"], name: "index_nevaeh_capabilities_on_intent_name"
    t.index ["slug"], name: "index_nevaeh_capabilities_on_slug", unique: true
  end

  create_table "nevaeh_construction_releases", force: :cascade do |t|
    t.bigint "nevaeh_construction_id", null: false
    t.integer "version", null: false
    t.jsonb "definition", default: {}, null: false
    t.jsonb "sample_tests", default: [], null: false
    t.jsonb "artifacts", default: {}, null: false
    t.jsonb "verification", default: {}, null: false
    t.string "fingerprint", null: false
    t.string "status", default: "built", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_construction_id", "version"], name: "idx_construction_release_version", unique: true
    t.index ["nevaeh_construction_id"], name: "idx_construction_release_parent"
  end

  create_table "nevaeh_constructions", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.string "name", null: false
    t.string "key", null: false
    t.text "description"
    t.jsonb "definition", default: {}, null: false
    t.jsonb "sample_tests", default: [], null: false
    t.string "status", default: "draft", null: false
    t.bigint "active_release_id"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_constructions_on_creator_id"
    t.index ["key"], name: "index_nevaeh_constructions_on_key", unique: true
  end

  create_table "nevaeh_conversation_turns", force: :cascade do |t|
    t.bigint "nevaeh_conversation_id", null: false
    t.string "request_key", null: false
    t.text "prompt", null: false
    t.text "response", null: false
    t.bigint "checkpoint_id", null: false
    t.jsonb "evidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_conversation_id", "request_key"], name: "idx_conversation_request", unique: true
    t.index ["nevaeh_conversation_id"], name: "idx_turn_conversation"
  end

  create_table "nevaeh_conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "nevaeh_language_model_id", null: false
    t.string "title", default: "Conversation", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_language_model_id"], name: "idx_conversation_model"
    t.index ["user_id"], name: "index_nevaeh_conversations_on_user_id"
  end

  create_table "nevaeh_dcp_deliveries", force: :cascade do |t|
    t.bigint "executive_case_id", null: false
    t.bigint "recipient_id", null: false
    t.string "key", null: false
    t.string "status", default: "pending", null: false
    t.string "sha256"
    t.string "rights_reference", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.string "error"
    t.datetime "received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["executive_case_id"], name: "index_nevaeh_dcp_deliveries_on_executive_case_id"
    t.index ["key"], name: "index_nevaeh_dcp_deliveries_on_key", unique: true
    t.index ["recipient_id"], name: "index_nevaeh_dcp_deliveries_on_recipient_id"
  end

  create_table "nevaeh_executive_cases", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.bigint "assignee_id"
    t.bigint "delivery_message_id"
    t.string "kind", limit: 20, null: false
    t.string "title", limit: 160, null: false
    t.text "details"
    t.string "status", limit: 20, default: "open", null: false
    t.datetime "due_at", null: false
    t.datetime "reminded_at"
    t.string "reference", limit: 240
    t.string "source_event", limit: 100
    t.text "review_note"
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_nevaeh_executive_cases_on_assignee_id"
    t.index ["delivery_message_id"], name: "index_nevaeh_executive_cases_on_delivery_message_id"
    t.index ["due_at"], name: "index_executive_cases_due_for_reminder", where: "((reminded_at IS NULL) AND ((status)::text <> 'closed'::text))"
    t.index ["owner_id", "source_event"], name: "index_nevaeh_executive_cases_on_owner_id_and_source_event", unique: true
    t.index ["owner_id"], name: "index_nevaeh_executive_cases_on_owner_id"
    t.index ["reviewer_id"], name: "index_nevaeh_executive_cases_on_reviewer_id"
  end

  create_table "nevaeh_executive_phone_routes", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.bigint "assignee_id"
    t.string "key", limit: 48, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignee_id"], name: "index_nevaeh_executive_phone_routes_on_assignee_id"
    t.index ["key"], name: "index_nevaeh_executive_phone_routes_on_key", unique: true
    t.index ["owner_id"], name: "index_nevaeh_executive_phone_routes_on_owner_id", unique: true
  end

  create_table "nevaeh_goal_steps", force: :cascade do |t|
    t.bigint "nevaeh_goal_id", null: false
    t.bigint "nevaeh_os_agent_id", null: false
    t.bigint "nevaeh_agent_run_id"
    t.string "key", null: false
    t.string "label", null: false
    t.integer "position", null: false
    t.string "status", default: "waiting", null: false
    t.json "command", default: {}, null: false
    t.json "expectations", default: [], null: false
    t.json "evidence", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_agent_run_id"], name: "index_nevaeh_goal_steps_on_nevaeh_agent_run_id"
    t.index ["nevaeh_goal_id", "key"], name: "index_nevaeh_goal_steps_on_nevaeh_goal_id_and_key", unique: true
    t.index ["nevaeh_goal_id"], name: "index_nevaeh_goal_steps_on_nevaeh_goal_id"
    t.index ["nevaeh_os_agent_id"], name: "index_nevaeh_goal_steps_on_nevaeh_os_agent_id"
  end

  create_table "nevaeh_goals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.string "request_key", null: false
    t.string "fingerprint", null: false
    t.string "status", default: "draft", null: false
    t.text "error"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "request_key"], name: "index_nevaeh_goals_on_user_id_and_request_key", unique: true
    t.index ["user_id"], name: "index_nevaeh_goals_on_user_id"
  end

  create_table "nevaeh_inference_models", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.jsonb "rules", default: [], null: false
    t.jsonb "examples", default: [], null: false
    t.jsonb "lexicon", default: {}, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "nevaeh_intelligences", force: :cascade do |t|
    t.string "name", null: false
    t.string "intent_key", null: false
    t.string "target_model"
    t.string "operation", null: false
    t.bigint "nevaeh_capability_id", null: false
    t.jsonb "instructions", default: {}, null: false
    t.string "status", default: "draft", null: false
    t.string "execution_mode", default: "async", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["intent_key"], name: "index_nevaeh_intelligences_on_intent_key", unique: true
    t.index ["nevaeh_capability_id"], name: "index_nevaeh_intelligences_on_nevaeh_capability_id"
    t.index ["status"], name: "index_nevaeh_intelligences_on_status"
  end

  create_table "nevaeh_islamic_passages", force: :cascade do |t|
    t.bigint "nevaeh_islamic_source_id", null: false
    t.string "reference", null: false
    t.text "body", null: false
    t.jsonb "assessments", default: [], null: false
    t.text "narrator"
    t.string "sha256", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_islamic_source_id", "reference"], name: "idx_islamic_passage_reference", unique: true
    t.index ["nevaeh_islamic_source_id"], name: "idx_islamic_passage_source"
  end

  create_table "nevaeh_islamic_sources", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.bigint "reviewer_id"
    t.datetime "reviewed_at"
    t.string "name", null: false
    t.string "kind", null: false
    t.string "language", null: false
    t.string "edition", null: false
    t.string "tradition"
    t.string "translator"
    t.text "source_url", null: false
    t.text "attribution", null: false
    t.text "license", null: false
    t.text "permission_evidence"
    t.boolean "training_permitted", default: false, null: false
    t.string "sha256", null: false
    t.string "status", default: "draft", null: false
    t.integer "passages_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_islamic_sources_on_creator_id"
    t.index ["reviewer_id"], name: "index_nevaeh_islamic_sources_on_reviewer_id"
    t.index ["sha256"], name: "index_nevaeh_islamic_sources_on_sha256", unique: true
  end

  create_table "nevaeh_language_bindings", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.bigint "nevaeh_manual_build_id"
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "patterns", default: [], null: false
    t.jsonb "slots", default: {}, null: false
    t.jsonb "command_template", default: {}, null: false
    t.jsonb "source_refs", default: [], null: false
    t.string "contract_sha256"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "builder_spec", default: {}, null: false
    t.jsonb "builder_verification", default: {}, null: false
    t.index ["creator_id"], name: "index_nevaeh_language_bindings_on_creator_id"
    t.index ["nevaeh_manual_build_id"], name: "idx_language_binding_build"
  end

  create_table "nevaeh_language_checkpoints", force: :cascade do |t|
    t.bigint "nevaeh_training_run_id", null: false
    t.bigint "nevaeh_language_model_id", null: false
    t.jsonb "weights", default: {}, null: false
    t.jsonb "metrics", default: {}, null: false
    t.string "sha256", null: false
    t.string "status", default: "candidate", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_language_model_id"], name: "idx_checkpoint_model"
    t.index ["nevaeh_training_run_id"], name: "idx_checkpoint_run", unique: true
  end

  create_table "nevaeh_language_models", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.bigint "active_checkpoint_id"
    t.string "visibility", default: "internal", null: false
    t.integer "hidden_size", default: 16, null: false
    t.integer "vocabulary_limit", default: 256, null: false
    t.boolean "enabled", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "nevaeh_learning_plans", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.bigint "language_model_id", null: false
    t.bigint "active_training_run_id"
    t.bigint "nevaeh_manual_build_id"
    t.string "name", null: false
    t.jsonb "dataset_ids", default: [], null: false
    t.integer "position", default: 0, null: false
    t.integer "attempt", default: 0, null: false
    t.integer "epochs", default: 3, null: false
    t.string "status", default: "paused", null: false
    t.text "error"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_training_run_id"], name: "index_nevaeh_learning_plans_on_active_training_run_id"
    t.index ["actor_id"], name: "index_nevaeh_learning_plans_on_actor_id"
    t.index ["language_model_id"], name: "index_nevaeh_learning_plans_on_language_model_id"
    t.index ["nevaeh_manual_build_id"], name: "idx_learning_plan_build"
  end

  create_table "nevaeh_manual_builds", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.string "name", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "manifest", default: [], null: false
    t.jsonb "dataset_ids", default: [], null: false
    t.jsonb "coverage", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_manual_builds_on_creator_id"
  end

  create_table "nevaeh_onboarding_cases", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "trial_id", null: false
    t.bigint "order_id", null: false
    t.bigint "playbook_id"
    t.datetime "paid_at", null: false
    t.datetime "dashboard_at"
    t.datetime "mailbox_at"
    t.datetime "followed_up_at"
    t.datetime "completed_at"
    t.datetime "closed_at"
    t.datetime "escalated_at"
    t.datetime "dashboard_escalated_at"
    t.string "blocker"
    t.string "evaluation_cohort"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "mailbox_attempts", default: 0, null: false
    t.datetime "mailbox_attempted_at"
    t.index ["operator_id", "closed_at"], name: "idx_onboarding_operator_cases"
    t.index ["operator_id"], name: "index_nevaeh_onboarding_cases_on_operator_id"
    t.index ["order_id"], name: "index_nevaeh_onboarding_cases_on_order_id", unique: true
    t.index ["playbook_id"], name: "index_nevaeh_onboarding_cases_on_playbook_id"
    t.index ["trial_id"], name: "index_nevaeh_onboarding_cases_on_trial_id"
  end

  create_table "nevaeh_onboarding_playbooks", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "parent_id"
    t.integer "escalate_after_hours", null: false
    t.string "status", null: false
    t.string "evidence_digest", null: false
    t.jsonb "evaluation", default: {}, null: false
    t.datetime "activated_at"
    t.datetime "retired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "evidence_digest"], name: "idx_onboarding_playbook_evidence", unique: true
    t.index ["operator_id"], name: "idx_onboarding_active_playbook", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["operator_id"], name: "index_nevaeh_onboarding_playbooks_on_operator_id"
    t.index ["parent_id"], name: "index_nevaeh_onboarding_playbooks_on_parent_id"
  end

  create_table "nevaeh_os_actions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "request_key", null: false
    t.jsonb "command", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.jsonb "result", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "request_key"], name: "index_nevaeh_os_actions_on_user_id_and_request_key", unique: true
    t.index ["user_id"], name: "index_nevaeh_os_actions_on_user_id"
  end

  create_table "nevaeh_os_agents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "role", default: "Assistant", null: false
    t.text "instructions"
    t.date "birth_date"
    t.string "birth_time"
    t.string "birth_place"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "system_key"
    t.boolean "enabled", default: true, null: false
    t.string "autonomy", default: "manual", null: false
    t.jsonb "allowed_capabilities", default: [], null: false
    t.datetime "deleted_at"
    t.index ["user_id", "system_key"], name: "index_nevaeh_os_agents_on_user_id_and_system_key", unique: true
    t.index ["user_id"], name: "index_nevaeh_os_agents_on_user_id"
  end

  create_table "nevaeh_os_consents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "category", null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "category"], name: "index_nevaeh_os_consents_on_user_id_and_category", unique: true
    t.index ["user_id"], name: "index_nevaeh_os_consents_on_user_id"
  end

  create_table "nevaeh_os_memories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "category", null: false
    t.text "text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_nevaeh_os_memories_on_user_id"
  end

  create_table "nevaeh_os_sources", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "url", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "sha256", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_nevaeh_os_sources_on_user_id"
  end

  create_table "nevaeh_resolution_observations", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "playbook_id"
    t.string "workflow", null: false
    t.bigint "subject_id", null: false
    t.string "comparison_key", null: false
    t.string "cohort", null: false
    t.datetime "started_at", null: false
    t.datetime "measured_at"
    t.jsonb "signals", default: {}, null: false
    t.jsonb "receipt", default: {}, null: false
    t.jsonb "outcome", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "workflow", "measured_at"], name: "idx_nevaeh_resolution_measurements"
    t.index ["operator_id"], name: "index_nevaeh_resolution_observations_on_operator_id"
    t.index ["playbook_id"], name: "index_nevaeh_resolution_observations_on_playbook_id"
    t.index ["workflow", "comparison_key"], name: "idx_nevaeh_resolution_comparison", unique: true
    t.index ["workflow", "subject_id"], name: "idx_nevaeh_resolution_subject", unique: true
  end

  create_table "nevaeh_resolution_playbooks", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.bigint "parent_id"
    t.string "workflow", null: false
    t.string "strategy", null: false
    t.string "status", null: false
    t.string "evidence_digest", null: false
    t.jsonb "evidence", default: {}, null: false
    t.datetime "activated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "workflow", "evidence_digest"], name: "idx_nevaeh_resolution_playbook_evidence", unique: true
    t.index ["operator_id", "workflow"], name: "idx_nevaeh_resolution_current_playbook", unique: true, where: "((status)::text = ANY ((ARRAY['trial'::character varying, 'active'::character varying])::text[]))"
    t.index ["operator_id"], name: "index_nevaeh_resolution_playbooks_on_operator_id"
    t.index ["parent_id"], name: "index_nevaeh_resolution_playbooks_on_parent_id"
  end

  create_table "nevaeh_speech_segments", force: :cascade do |t|
    t.bigint "nevaeh_speech_id", null: false
    t.integer "position", null: false
    t.text "text", null: false
    t.string "status", default: "queued", null: false
    t.float "duration"
    t.json "mouth_frames", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_speech_id", "position"], name: "index_nevaeh_speech_segments_on_nevaeh_speech_id_and_position", unique: true
    t.index ["nevaeh_speech_id"], name: "index_nevaeh_speech_segments_on_nevaeh_speech_id"
  end

  create_table "nevaeh_speeches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "request_key", null: false
    t.string "fingerprint", null: false
    t.text "text", null: false
    t.string "voice", default: "en-us+f3", null: false
    t.integer "speed", default: 170, null: false
    t.string "status", default: "queued", null: false
    t.float "duration"
    t.json "mouth_frames", default: [], null: false
    t.boolean "truncated", default: false, null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_nevaeh_speeches_on_expires_at"
    t.index ["status", "started_at"], name: "index_nevaeh_speeches_on_status_and_started_at"
    t.index ["user_id", "request_key"], name: "index_nevaeh_speeches_on_user_id_and_request_key", unique: true
    t.index ["user_id"], name: "index_nevaeh_speeches_on_user_id"
  end

  create_table "nevaeh_studio_idempotency_records", force: :cascade do |t|
    t.string "operation_key", null: false
    t.bigint "ticket_id", null: false
    t.string "work_order_sha256", null: false
    t.string "inputs_sha256", null: false
    t.bigint "work_item_id", null: false
    t.bigint "studio_project_id", null: false
    t.bigint "production_id", null: false
    t.bigint "studio_scene_id", null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_key"], name: "idx_nevaeh_studio_idempotency_operation_unique", unique: true
    t.index ["ticket_id"], name: "idx_nevaeh_studio_idempotency_ticket"
    t.index ["work_item_id"], name: "idx_nevaeh_studio_idempotency_work_item"
  end

  create_table "nevaeh_study_routines", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.bigint "source_id", null: false
    t.bigint "language_model_id"
    t.string "name", null: false
    t.jsonb "daily_times", default: {}, null: false
    t.jsonb "dataset_ids", default: [], null: false
    t.boolean "enabled", default: false, null: false
    t.boolean "training_enabled", default: false, null: false
    t.boolean "auto_activate", default: true, null: false
    t.integer "window_minutes", default: 15, null: false
    t.integer "passages_per_session", default: 10, null: false
    t.integer "training_epochs", default: 3, null: false
    t.bigint "reading_after_id", default: 0, null: false
    t.integer "training_cursor", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.text "last_error"
    t.datetime "last_tick_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_study_routines_on_creator_id"
    t.index ["language_model_id"], name: "index_nevaeh_study_routines_on_language_model_id"
    t.index ["source_id"], name: "index_nevaeh_study_routines_on_source_id"
  end

  create_table "nevaeh_study_sessions", force: :cascade do |t|
    t.bigint "nevaeh_study_routine_id", null: false
    t.bigint "nevaeh_training_run_id"
    t.date "local_date", null: false
    t.string "slot", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.jsonb "reading_evidence", default: [], null: false
    t.jsonb "result", default: {}, null: false
    t.string "lease_token"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_study_routine_id", "local_date", "slot"], name: "idx_study_session_daily_slot", unique: true
    t.index ["nevaeh_study_routine_id"], name: "idx_study_session_routine"
    t.index ["nevaeh_training_run_id"], name: "idx_study_session_training"
  end

  create_table "nevaeh_task_dialogues", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "request_key", null: false
    t.string "status", default: "collecting", null: false
    t.text "request_text", null: false
    t.string "catalog_sha256", null: false
    t.jsonb "plan", default: [], null: false
    t.jsonb "context", default: {}, null: false
    t.jsonb "interpretation", default: {}, null: false
    t.jsonb "response", default: {}, null: false
    t.bigint "nevaeh_os_action_id"
    t.bigint "nevaeh_goal_id"
    t.datetime "expires_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_goal_id"], name: "index_nevaeh_task_dialogues_on_nevaeh_goal_id"
    t.index ["nevaeh_os_action_id"], name: "index_nevaeh_task_dialogues_on_nevaeh_os_action_id"
    t.index ["user_id", "request_key"], name: "index_nevaeh_task_dialogues_on_user_id_and_request_key", unique: true
    t.index ["user_id"], name: "index_nevaeh_task_dialogues_on_user_id"
  end

  create_table "nevaeh_task_examples", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "nevaeh_task_dialogue_id", null: false
    t.text "phrase", null: false
    t.string "phrase_sha256", null: false
    t.string "task_key", null: false
    t.string "catalog_sha256", null: false
    t.string "status", default: "active", null: false
    t.jsonb "evidence", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_task_dialogue_id"], name: "index_nevaeh_task_examples_on_nevaeh_task_dialogue_id"
    t.index ["user_id", "phrase_sha256", "catalog_sha256"], name: "idx_nevaeh_reviewed_task_phrase", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["user_id"], name: "index_nevaeh_task_examples_on_user_id"
  end

  create_table "nevaeh_task_turns", force: :cascade do |t|
    t.bigint "nevaeh_task_dialogue_id", null: false
    t.string "request_key", null: false
    t.string "input_sha256", null: false
    t.jsonb "input", default: {}, null: false
    t.jsonb "response", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_task_dialogue_id", "request_key"], name: "idx_nevaeh_task_turn_delivery", unique: true
    t.index ["nevaeh_task_dialogue_id"], name: "index_nevaeh_task_turns_on_nevaeh_task_dialogue_id"
  end

  create_table "nevaeh_test_runs", force: :cascade do |t|
    t.string "run_id", null: false
    t.string "status", null: false
    t.string "capability_slug"
    t.bigint "nevaeh_capability_id"
    t.bigint "marlon_ticket_id"
    t.string "correlation_id"
    t.string "git_sha"
    t.string "environment"
    t.integer "exit_status"
    t.integer "tests_count"
    t.integer "assertions_count"
    t.integer "failures_count"
    t.integer "errors_count"
    t.integer "skips_count"
    t.decimal "duration_seconds", precision: 12, scale: 3
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string "output_sha256", null: false
    t.string "report_path", null: false
    t.string "output_path", null: false
    t.jsonb "report", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["capability_slug", "created_at"], name: "index_nevaeh_test_runs_on_capability_slug_and_created_at"
    t.index ["correlation_id"], name: "index_nevaeh_test_runs_on_correlation_id"
    t.index ["marlon_ticket_id"], name: "index_nevaeh_test_runs_on_marlon_ticket_id"
    t.index ["run_id"], name: "index_nevaeh_test_runs_on_run_id", unique: true
  end

  create_table "nevaeh_training_datasets", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.jsonb "examples", default: [], null: false
    t.jsonb "provenance", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_training_datasets_on_creator_id"
  end

  create_table "nevaeh_training_runs", force: :cascade do |t|
    t.bigint "nevaeh_language_model_id", null: false
    t.bigint "nevaeh_training_dataset_id", null: false
    t.bigint "actor_id", null: false
    t.string "status", default: "queued", null: false
    t.string "request_key", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.jsonb "metrics", default: {}, null: false
    t.text "error"
    t.datetime "started_at"
    t.datetime "heartbeat_at"
    t.string "lease_token"
    t.integer "epochs", default: 10, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_nevaeh_training_runs_on_actor_id"
    t.index ["nevaeh_language_model_id", "request_key"], name: "idx_training_run_request", unique: true
    t.index ["nevaeh_language_model_id"], name: "idx_training_run_model"
    t.index ["nevaeh_training_dataset_id"], name: "idx_training_run_dataset"
    t.index ["status"], name: "idx_single_neural_training_lease", unique: true, where: "((status)::text = 'running'::text)"
  end

  create_table "nevaeh_travel_bookings", force: :cascade do |t|
    t.bigint "executive_case_id", null: false
    t.string "kind", null: false
    t.string "source_id", null: false
    t.string "status", default: "quoted", null: false
    t.string "amount", null: false
    t.string "currency", null: false
    t.json "quote", default: {}, null: false
    t.string "supplier_id"
    t.string "reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["executive_case_id", "kind", "source_id"], name: "idx_on_executive_case_id_kind_source_id_d4ae1f8003", unique: true
    t.index ["executive_case_id"], name: "index_nevaeh_travel_bookings_on_executive_case_id"
  end

  create_table "nevaeh_watch_events", force: :cascade do |t|
    t.bigint "nevaeh_watcher_id", null: false
    t.bigint "nevaeh_agent_run_id"
    t.string "event_key", null: false
    t.string "entity", null: false
    t.string "change", null: false
    t.jsonb "before_value", default: {}, null: false
    t.jsonb "after_value", default: {}, null: false
    t.jsonb "plan", default: {}, null: false
    t.string "status", default: "detected", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_agent_run_id"], name: "index_nevaeh_watch_events_on_nevaeh_agent_run_id"
    t.index ["nevaeh_watcher_id", "event_key"], name: "idx_nevaeh_watch_event_identity", unique: true
    t.index ["nevaeh_watcher_id"], name: "index_nevaeh_watch_events_on_nevaeh_watcher_id"
  end

  create_table "nevaeh_watchers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "nevaeh_os_agent_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.jsonb "target", default: {}, null: false
    t.string "condition", default: "updated", null: false
    t.string "response", default: "prepare", null: false
    t.jsonb "command_template", default: {}, null: false
    t.string "status", default: "active", null: false
    t.integer "interval_minutes", default: 60, null: false
    t.jsonb "baseline", default: {}, null: false
    t.boolean "initialized", default: false, null: false
    t.datetime "next_poll_at"
    t.datetime "last_polled_at"
    t.string "lease_token"
    t.datetime "lease_expires_at"
    t.integer "poll_sequence", default: 0, null: false
    t.integer "failures", default: 0, null: false
    t.text "error"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_os_agent_id"], name: "index_nevaeh_watchers_on_nevaeh_os_agent_id"
    t.index ["status", "next_poll_at"], name: "index_nevaeh_watchers_on_status_and_next_poll_at"
    t.index ["user_id"], name: "index_nevaeh_watchers_on_user_id"
  end

  create_table "nevaeh_worker_report_reviews", force: :cascade do |t|
    t.bigint "nevaeh_worker_report_id", null: false
    t.bigint "user_id", null: false
    t.string "verdict", null: false
    t.string "receipt_sha256", null: false
    t.text "lesson", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nevaeh_worker_report_id"], name: "index_nevaeh_worker_report_reviews_on_nevaeh_worker_report_id"
    t.index ["user_id"], name: "index_nevaeh_worker_report_reviews_on_user_id"
  end

  create_table "nevaeh_worker_reports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "nevaeh_os_agent_id", null: false
    t.bigint "nevaeh_agent_run_id", null: false
    t.string "capability", null: false
    t.string "site_key", null: false
    t.string "contract_sha256", null: false
    t.string "receipt_sha256", null: false
    t.string "status", null: false
    t.jsonb "evidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "structured_result", default: {}, null: false
    t.index ["nevaeh_agent_run_id"], name: "index_nevaeh_worker_reports_on_nevaeh_agent_run_id", unique: true
    t.index ["nevaeh_os_agent_id"], name: "index_nevaeh_worker_reports_on_nevaeh_os_agent_id"
    t.index ["user_id", "nevaeh_os_agent_id", "capability", "site_key"], name: "idx_nevaeh_worker_report_context"
    t.index ["user_id"], name: "index_nevaeh_worker_reports_on_user_id"
  end

  create_table "nevaeh_workflow_runs", force: :cascade do |t|
    t.bigint "nevaeh_workflow_id", null: false
    t.bigint "actor_id", null: false
    t.bigint "ticket_id"
    t.string "request_key", null: false
    t.string "status", default: "queued", null: false
    t.jsonb "snapshot", default: {}, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_nevaeh_workflow_runs_on_actor_id"
    t.index ["nevaeh_workflow_id", "request_key"], name: "idx_nevaeh_run_request", unique: true
    t.index ["nevaeh_workflow_id"], name: "index_nevaeh_workflow_runs_on_nevaeh_workflow_id"
    t.index ["ticket_id"], name: "index_nevaeh_workflow_runs_on_ticket_id", unique: true
  end

  create_table "nevaeh_workflows", force: :cascade do |t|
    t.bigint "creator_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.jsonb "sections", default: [], null: false
    t.integer "interval_minutes"
    t.datetime "next_run_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_nevaeh_workflows_on_creator_id"
    t.index ["status", "next_run_at"], name: "index_nevaeh_workflows_on_status_and_next_run_at"
  end

  create_table "nevaeh_workspace_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "navigation", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_nevaeh_workspace_preferences_on_user_id", unique: true
  end

  create_table "nevaeh_workspaces", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.json "panels", default: [], null: false
    t.string "active_key"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_nevaeh_workspaces_on_user_id", unique: true
  end

  create_table "nevaeh_writing_profiles", force: :cascade do |t|
    t.string "name", null: false
    t.string "format", null: false
    t.string "provider", default: "rules", null: false
    t.bigint "inference_model_id"
    t.text "instructions"
    t.jsonb "templates", default: [], null: false
    t.jsonb "examples", default: [], null: false
    t.boolean "enabled", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "language_model_id"
    t.index ["inference_model_id"], name: "index_nevaeh_writing_profiles_on_inference_model_id"
    t.index ["language_model_id"], name: "index_nevaeh_writing_profiles_on_language_model_id"
  end

  create_table "nevaehs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_nevaehs_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "community_id"
    t.bigint "site_id"
    t.bigint "parent_id"
    t.string "title"
    t.string "kind", default: "post", null: false
    t.string "visibility", default: "public", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "expires_at"
    t.string "request_key"
    t.string "audience", default: "everyone", null: false
    t.string "distribution", default: "lightek_social", null: false
    t.string "moderation_state", default: "published", null: false
    t.index ["community_id"], name: "index_posts_on_community_id"
    t.index ["parent_id"], name: "index_posts_on_parent_id"
    t.index ["site_id", "community_id", "created_at"], name: "index_posts_on_site_id_and_community_id_and_created_at"
    t.index ["site_id", "distribution"], name: "index_posts_on_site_id_and_distribution"
    t.index ["site_id", "moderation_state"], name: "index_posts_on_site_id_and_moderation_state"
    t.index ["site_id"], name: "index_posts_on_site_id"
    t.index ["user_id", "request_key"], name: "index_posts_on_user_id_and_request_key", unique: true
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "productions", force: :cascade do |t|
    t.bigint "studio_project_id", null: false
    t.string "name", null: false
    t.string "kind", default: "general", null: false
    t.string "status", default: "development", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_productions_on_status"
    t.index ["studio_project_id", "name"], name: "index_productions_on_studio_project_id_and_name"
    t.index ["studio_project_id"], name: "index_productions_on_studio_project_id"
  end

  create_table "profile_sections", force: :cascade do |t|
    t.bigint "profile_id", null: false
    t.string "key", null: false
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id", "key"], name: "index_profile_sections_on_profile_id_and_key", unique: true
    t.index ["profile_id", "position"], name: "index_profile_sections_on_profile_id_and_position"
    t.index ["profile_id"], name: "index_profile_sections_on_profile_id"
  end

  create_table "profile_visits", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "profile_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id"], name: "index_profile_visits_on_profile_id"
    t.index ["user_id"], name: "index_profile_visits_on_user_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "bio"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "display_name"
    t.string "handle", null: false
    t.string "profile_type", default: "person", null: false
    t.string "avatar_url"
    t.string "cover_image_url"
    t.string "community_gender", default: "unspecified", null: false
    t.integer "top_people_limit", default: 8, null: false
    t.index ["handle"], name: "index_profiles_on_handle", unique: true
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "provisioning_profiles", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "purpose", null: false
    t.string "os_image", default: "ubuntu-24.04", null: false
    t.integer "cpu_cores"
    t.integer "memory_mb"
    t.integer "disk_gb"
    t.boolean "backups_enabled", default: true, null: false
    t.boolean "monitoring_enabled", default: true, null: false
    t.jsonb "services", default: [], null: false
    t.jsonb "firewall_rules", default: [], null: false
    t.jsonb "configuration", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_provisioning_profiles_on_slug", unique: true
  end

  create_table "provisioning_requests", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.bigint "subscription_id"
    t.bigint "subscription_plan_id"
    t.bigint "subscription_infrastructure_entitlement_id"
    t.bigint "provisioning_profile_id"
    t.bigint "compute_policy_id"
    t.bigint "compute_provider_id"
    t.bigint "gatekeeper_operation_id"
    t.integer "requested_node_count", default: 1, null: false
    t.integer "estimated_monthly_cost_cents"
    t.string "approval_status", default: "pending", null: false
    t.string "execution_status", default: "draft", null: false
    t.text "approval_reason"
    t.string "approved_by"
    t.datetime "approved_at"
    t.string "error_class"
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "selected_region"
    t.string "selected_plan"
    t.string "selected_image"
    t.string "node_label"
    t.bigint "gatekeeper_node_id"
    t.string "destroy_approval_status", default: "not_requested", null: false
    t.string "destroy_approved_by"
    t.datetime "destroy_approved_at"
    t.datetime "provisioned_at"
    t.datetime "destroyed_at"
    t.index ["approval_status"], name: "index_provisioning_requests_on_approval_status"
    t.index ["compute_policy_id"], name: "index_provisioning_requests_on_compute_policy_id"
    t.index ["compute_provider_id"], name: "index_provisioning_requests_on_compute_provider_id"
    t.index ["created_at"], name: "index_provisioning_requests_on_created_at"
    t.index ["destroy_approval_status"], name: "index_provisioning_requests_on_destroy_approval_status"
    t.index ["execution_status"], name: "index_provisioning_requests_on_execution_status"
    t.index ["gatekeeper_node_id"], name: "index_provisioning_requests_on_gatekeeper_node_id"
    t.index ["gatekeeper_operation_id"], name: "index_provisioning_requests_on_gatekeeper_operation_id"
    t.index ["owner_type", "owner_id"], name: "index_provisioning_requests_on_owner_type_and_owner_id"
    t.index ["provisioning_profile_id"], name: "index_provisioning_requests_on_provisioning_profile_id"
    t.index ["subscription_id"], name: "index_provisioning_requests_on_subscription_id"
    t.index ["subscription_infrastructure_entitlement_id"], name: "idx_on_subscription_infrastructure_entitlement_id_3e947bde14"
    t.index ["subscription_plan_id"], name: "index_provisioning_requests_on_subscription_plan_id"
  end

  create_table "release_assurance_assignments", force: :cascade do |t|
    t.bigint "tester_id", null: false
    t.bigint "environment_id", null: false
    t.string "scenario", null: false
    t.string "invite_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "redeemed_at"
    t.datetime "account_revoked_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["environment_id"], name: "index_release_assurance_assignments_on_environment_id"
    t.index ["invite_digest"], name: "index_release_assurance_assignments_on_invite_digest", unique: true
    t.index ["tester_id"], name: "index_release_assurance_assignments_on_tester_id"
  end

  create_table "release_assurance_candidates", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "name", null: false
    t.string "profile", null: false
    t.string "publication_key", null: false
    t.jsonb "selectors", default: [], null: false
    t.string "base_sha"
    t.jsonb "sources", default: [], null: false
    t.string "source_sha"
    t.jsonb "conflicts", default: [], null: false
    t.string "state", default: "queued", null: false
    t.string "assembly_error"
    t.bigint "promotion_approver_id"
    t.datetime "promotion_approved_at"
    t.string "promotion_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id"], name: "index_release_assurance_candidates_on_operator_id"
    t.index ["promotion_approver_id"], name: "index_release_assurance_candidates_on_promotion_approver_id"
    t.index ["publication_key"], name: "index_release_assurance_candidates_on_publication_key", unique: true
  end

  create_table "release_assurance_defects", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "run_id", null: false
    t.bigint "retest_id"
    t.string "status", default: "open", null: false
    t.bigint "ticket_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_release_assurance_defects_on_candidate_id"
    t.index ["retest_id"], name: "index_release_assurance_defects_on_retest_id"
    t.index ["run_id"], name: "index_release_assurance_defects_on_run_id", unique: true
  end

  create_table "release_assurance_environments", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "provisioning_request_id", null: false
    t.bigint "deployment_operation_id"
    t.string "hostname", null: false
    t.integer "budget_cents", null: false
    t.datetime "expires_at", null: false
    t.string "state", default: "prepared", null: false
    t.string "approval_digest"
    t.string "failure"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_release_assurance_environments_on_candidate_id"
    t.index ["deployment_operation_id"], name: "idx_on_deployment_operation_id_d51ee3451b"
    t.index ["expires_at"], name: "index_release_assurance_environments_on_expires_at"
    t.index ["hostname"], name: "index_release_assurance_environments_on_hostname", unique: true
    t.index ["provisioning_request_id"], name: "idx_on_provisioning_request_id_31c0d34b24", unique: true
  end

  create_table "release_assurance_runs", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "environment_id"
    t.bigint "assignment_id"
    t.string "check_key", null: false
    t.string "kind", null: false
    t.string "result", null: false
    t.string "source_sha", null: false
    t.string "external_id"
    t.jsonb "evidence", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_id"], name: "index_release_assurance_runs_on_assignment_id"
    t.index ["candidate_id", "check_key", "external_id"], name: "idx_release_acceptance_receipt", unique: true
    t.index ["candidate_id"], name: "index_release_assurance_runs_on_candidate_id"
    t.index ["environment_id"], name: "index_release_assurance_runs_on_environment_id"
  end

  create_table "release_assurance_testers", force: :cascade do |t|
    t.bigint "operator_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "platform", null: false
    t.string "device_profile", null: false
    t.datetime "consented_at", null: false
    t.datetime "offboarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "email", "platform"], name: "idx_release_tester_identity", unique: true
    t.index ["operator_id"], name: "index_release_assurance_testers_on_operator_id"
  end

  create_table "release_assurance_workflows", force: :cascade do |t|
    t.bigint "candidate_id", null: false
    t.bigint "environment_id"
    t.string "source_sha", null: false
    t.integer "definition_version", null: false
    t.jsonb "steps", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "environment_id"], name: "idx_release_active_staging_workflow", unique: true, where: "((finished_at IS NULL) AND (environment_id IS NOT NULL))"
    t.index ["candidate_id"], name: "idx_release_active_ci_workflow", unique: true, where: "((finished_at IS NULL) AND (environment_id IS NULL))"
    t.index ["candidate_id"], name: "index_release_assurance_workflows_on_candidate_id"
    t.index ["environment_id"], name: "index_release_assurance_workflows_on_environment_id"
  end

  create_table "resellers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "scene_objects", force: :cascade do |t|
    t.bigint "studio_scene_id", null: false
    t.string "name", null: false
    t.string "object_type", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "definition", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["studio_scene_id", "position"], name: "index_scene_objects_on_studio_scene_id_and_position"
    t.index ["studio_scene_id"], name: "index_scene_objects_on_studio_scene_id"
  end

  create_table "sending_policies", force: :cascade do |t|
    t.string "name"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "connect_delegation", default: {}, null: false
    t.datetime "mfa_verified_at"
    t.boolean "mfa_enrollment_only", default: false, null: false
    t.bigint "identity_connection_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shows", force: :cascade do |t|
    t.string "title"
    t.string "network"
    t.bigint "episode_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id"], name: "index_shows_on_episode_id"
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

  create_table "studio_ad_campaigns", force: :cascade do |t|
    t.bigint "network_id", null: false
    t.bigint "asset_id", null: false
    t.bigint "blob_id", null: false
    t.string "name", null: false
    t.integer "seconds", null: false
    t.integer "rate_cents", null: false
    t.integer "network_bps", null: false
    t.integer "producer_bps", null: false
    t.integer "platform_bps", null: false
    t.boolean "open_for_booking", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exchange_key"
    t.string "creative_sha256"
    t.boolean "exchange_authority", default: true, null: false
    t.index ["asset_id"], name: "index_studio_ad_campaigns_on_asset_id"
    t.index ["exchange_key"], name: "index_studio_ad_campaigns_on_exchange_key", unique: true, where: "exchange_authority"
    t.index ["network_id", "exchange_key"], name: "index_studio_ad_campaigns_on_network_id_and_exchange_key", unique: true
    t.index ["network_id"], name: "index_studio_ad_campaigns_on_network_id"
  end

  create_table "studio_ad_demand_sources", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "vault_slug", null: false
    t.string "platform", default: "both", null: false
    t.integer "position", default: 0, null: false
    t.boolean "enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "name"], name: "index_studio_ad_demand_sources_on_site_id_and_name", unique: true
  end

  create_table "studio_ad_memberships", force: :cascade do |t|
    t.bigint "network_id", null: false
    t.bigint "station_site_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["network_id"], name: "index_studio_ad_memberships_on_network_id"
    t.index ["station_site_id", "network_id"], name: "index_studio_ad_memberships_on_station_site_id_and_network_id", unique: true
    t.index ["station_site_id"], name: "index_studio_ad_memberships_on_station_site_id"
  end

  create_table "studio_ad_networks", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exchange_key"
    t.boolean "imported", default: false, null: false
    t.bigint "peer_id"
    t.index ["peer_id"], name: "index_studio_ad_networks_on_peer_id"
    t.index ["site_id", "exchange_key"], name: "index_studio_ad_networks_on_site_id_and_exchange_key", unique: true
    t.index ["site_id"], name: "index_studio_ad_networks_on_site_id"
  end

  create_table "studio_ad_payments", force: :cascade do |t|
    t.bigint "placement_id", null: false
    t.string "public_key", null: false
    t.integer "amount_cents", null: false
    t.string "state", default: "unfunded", null: false
    t.integer "checkout_attempt", default: 0, null: false
    t.integer "checkout_amount_cents"
    t.string "checkout_reference"
    t.datetime "checkout_requested_at"
    t.string "intent_reference"
    t.string "charge_reference"
    t.datetime "authorized_until"
    t.datetime "captured_at"
    t.datetime "reconcile_after"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["charge_reference"], name: "index_studio_ad_payments_on_charge_reference", unique: true
    t.index ["checkout_reference"], name: "index_studio_ad_payments_on_checkout_reference", unique: true
    t.index ["intent_reference"], name: "index_studio_ad_payments_on_intent_reference", unique: true
    t.index ["placement_id"], name: "index_studio_ad_payments_on_placement_id", unique: true
    t.index ["public_key"], name: "index_studio_ad_payments_on_public_key", unique: true
    t.index ["state", "reconcile_after"], name: "index_studio_ad_payments_on_state_and_reconcile_after"
  end

  create_table "studio_ad_payouts", force: :cascade do |t|
    t.bigint "payment_id", null: false
    t.bigint "recipient_id", null: false
    t.string "role", null: false
    t.integer "amount_cents", null: false
    t.string "destination"
    t.datetime "requested_at"
    t.string "transfer_reference"
    t.string "reversal_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payment_id", "role"], name: "index_studio_ad_payouts_on_payment_id_and_role", unique: true
    t.index ["payment_id"], name: "index_studio_ad_payouts_on_payment_id"
    t.index ["recipient_id"], name: "index_studio_ad_payouts_on_recipient_id"
    t.index ["transfer_reference"], name: "index_studio_ad_payouts_on_transfer_reference", unique: true
  end

  create_table "studio_ad_placements", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "station_site_id", null: false
    t.bigint "airing_id"
    t.integer "row_index", null: false
    t.bigint "producer_id"
    t.integer "station_cents", null: false
    t.integer "producer_cents", null: false
    t.integer "network_cents", null: false
    t.integer "platform_cents", null: false
    t.datetime "delivered_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "peer_id"
    t.string "exchange_key"
    t.datetime "scheduled_start"
    t.datetime "scheduled_end"
    t.boolean "remote_retired", default: false, null: false
    t.datetime "remote_authorized_until"
    t.string "remote_state"
    t.datetime "sync_after"
    t.index ["airing_id", "row_index"], name: "index_studio_ad_placements_on_airing_id_and_row_index", unique: true
    t.index ["campaign_id"], name: "index_studio_ad_placements_on_campaign_id"
    t.index ["exchange_key"], name: "index_studio_ad_placements_on_exchange_key", unique: true
    t.index ["peer_id"], name: "index_studio_ad_placements_on_peer_id"
    t.index ["station_site_id"], name: "index_studio_ad_placements_on_station_site_id"
    t.index ["sync_after"], name: "index_studio_ad_placements_on_sync_after"
  end

  create_table "studio_ad_provider_statements", force: :cascade do |t|
    t.bigint "source_id", null: false
    t.string "reference", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.bigint "impressions", null: false
    t.bigint "reported_cents", null: false
    t.bigint "received_cents"
    t.string "deposit_reference"
    t.datetime "reconciled_at"
    t.bigint "reconciled_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "reference"], name: "index_studio_ad_provider_statements_on_source_id_and_reference", unique: true
  end

  create_table "studio_ad_stream_profiles", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "channel_id", null: false
    t.string "platform", null: false
    t.string "playback_url", null: false
    t.string "decision_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["decision_key"], name: "index_studio_ad_stream_profiles_on_decision_key", unique: true
    t.index ["site_id", "channel_id", "platform"], name: "idx_studio_ad_stream_profiles", unique: true
  end

  create_table "studio_ad_viewing_links", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "linked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code_digest"], name: "index_studio_ad_viewing_links_on_code_digest", unique: true
    t.index ["site_id", "user_id"], name: "index_studio_ad_viewing_links_on_site_id_and_user_id"
  end

  create_table "studio_ad_viewing_offers", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_studio_ad_viewing_offers_on_site_id", unique: true
  end

  create_table "studio_animation_previews", force: :cascade do |t|
    t.bigint "studio_asset_id", null: false
    t.string "variant_digest", null: false
    t.json "settings", null: false
    t.string "status", default: "queued", null: false
    t.string "attempt_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["studio_asset_id", "variant_digest"], name: "idx_on_studio_asset_id_variant_digest_5ce4d83076", unique: true
    t.index ["studio_asset_id"], name: "index_studio_animation_previews_on_studio_asset_id"
  end

  create_table "studio_assets", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.bigint "site_id"
    t.bigint "studio_project_id"
    t.string "name", null: false
    t.string "kind", null: false
    t.string "status", default: "uploaded", null: false
    t.string "request_key", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "animation_role"
    t.string "dimension_mode"
    t.index ["owner_id", "request_key"], name: "index_studio_assets_on_owner_id_and_request_key", unique: true
    t.index ["owner_id"], name: "index_studio_assets_on_owner_id"
    t.index ["site_id"], name: "index_studio_assets_on_site_id"
    t.index ["studio_project_id"], name: "index_studio_assets_on_studio_project_id"
  end

  create_table "studio_broadcast_applications", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "slug", null: false
    t.string "name", null: false
    t.string "platform", default: "roku", null: false
    t.string "status", default: "draft", null: false
    t.string "minimum_client_version", default: "1.0.0", null: false
    t.jsonb "settings", default: {}, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "slug"], name: "index_studio_broadcast_applications_on_site_id_and_slug", unique: true
    t.index ["site_id"], name: "index_studio_broadcast_applications_on_site_id"
  end

  create_table "studio_broadcast_channels", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.string "playback_url"
    t.string "image_url"
    t.text "description"
    t.integer "position", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "managed_playout", default: false, null: false
    t.bigint "backup_asset_id"
    t.bigint "backup_blob_id"
    t.index ["site_id"], name: "index_studio_broadcast_channels_on_site_id"
  end

  create_table "studio_broadcast_contract_evidence", force: :cascade do |t|
    t.bigint "version_id", null: false
    t.bigint "recorded_by_id", null: false
    t.string "reference", null: false
    t.string "kind", null: false
    t.bigint "quantity", null: false
    t.date "occurred_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recorded_by_id"], name: "index_studio_broadcast_contract_evidence_on_recorded_by_id"
    t.index ["version_id", "kind", "reference"], name: "index_broadcast_contract_evidence_on_reference", unique: true
    t.index ["version_id"], name: "index_studio_broadcast_contract_evidence_on_version_id"
  end

  create_table "studio_broadcast_contract_signatures", force: :cascade do |t|
    t.bigint "version_id", null: false
    t.bigint "signer_id", null: false
    t.string "party", null: false
    t.string "signer_name", null: false
    t.string "document_digest", null: false
    t.datetime "signed_at", null: false
    t.index ["signer_id"], name: "index_studio_broadcast_contract_signatures_on_signer_id"
    t.index ["version_id", "party"], name: "index_broadcast_contract_signatures_on_party", unique: true
    t.index ["version_id"], name: "index_studio_broadcast_contract_signatures_on_version_id"
  end

  create_table "studio_broadcast_contract_versions", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "offered_by_id", null: false
    t.integer "number", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.json "terms_snapshot", null: false
    t.string "document_digest", null: false
    t.datetime "withdrawn_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "number"], name: "index_broadcast_contract_versions_on_number", unique: true
    t.index ["contract_id"], name: "index_studio_broadcast_contract_versions_on_contract_id"
    t.index ["offered_by_id"], name: "index_studio_broadcast_contract_versions_on_offered_by_id"
  end

  create_table "studio_broadcast_contracts", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "counterparty_id"
    t.bigint "carriage_agreement_id"
    t.bigint "sponsor_package_id"
    t.string "kind", null: false
    t.string "title", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["carriage_agreement_id"], name: "index_studio_broadcast_contracts_on_carriage_agreement_id", unique: true
    t.index ["counterparty_id"], name: "index_studio_broadcast_contracts_on_counterparty_id"
    t.index ["site_id"], name: "index_studio_broadcast_contracts_on_site_id"
    t.index ["sponsor_package_id"], name: "index_studio_broadcast_contracts_on_sponsor_package_id", unique: true
  end

  create_table "studio_broadcast_delivery_rates", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.decimal "egress", precision: 12, scale: 6, null: false
    t.decimal "storage", precision: 12, scale: 6, null: false
    t.decimal "encoding", precision: 12, scale: 6, null: false
    t.decimal "support", precision: 12, scale: 6, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id"], name: "index_studio_broadcast_delivery_rates_on_site_id", unique: true
  end

  create_table "studio_broadcast_delivery_usage", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "channel_key", null: false
    t.date "day", null: false
    t.bigint "bytes_served", default: 0, null: false
    t.bigint "encoding_ms", default: 0, null: false
    t.bigint "stored_bytes", default: 0, null: false
    t.bigint "support_minutes", default: 0, null: false
    t.index ["site_id", "channel_key", "day"], name: "idx_broadcast_delivery_usage", unique: true
  end

  create_table "studio_broadcast_feed_incidents", force: :cascade do |t|
    t.bigint "hosted_carriage_id", null: false
    t.string "event", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hosted_carriage_id", "created_at"], name: "index_broadcast_feed_incidents_on_time"
    t.index ["hosted_carriage_id"], name: "index_studio_broadcast_feed_incidents_on_hosted_carriage_id"
  end

  create_table "studio_broadcast_operating_plans", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "department_id", null: false
    t.bigint "owner_id", null: false
    t.bigint "channel_id"
    t.string "market"
    t.date "month", null: false
    t.text "coverage", null: false
    t.text "targets", null: false
    t.bigint "budget_cents", null: false
    t.bigint "actual_cost_cents", null: false
    t.bigint "actual_revenue_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_studio_broadcast_operating_plans_on_channel_id"
    t.index ["department_id"], name: "index_studio_broadcast_operating_plans_on_department_id"
    t.index ["owner_id"], name: "index_studio_broadcast_operating_plans_on_owner_id"
    t.index ["site_id"], name: "index_studio_broadcast_operating_plans_on_site_id"
  end

  create_table "studio_broadcast_programs", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "post_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "starts_at"], name: "index_studio_broadcast_programs_on_channel_id_and_starts_at"
    t.index ["channel_id"], name: "index_studio_broadcast_programs_on_channel_id"
    t.index ["post_id"], name: "index_studio_broadcast_programs_on_post_id"
  end

  create_table "studio_broadcast_report_archives", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.date "month", null: false
    t.text "csv", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "month"], name: "index_studio_broadcast_report_archives_on_site_id_and_month", unique: true
    t.index ["site_id"], name: "index_studio_broadcast_report_archives_on_site_id"
  end

  create_table "studio_broadcast_view_sessions", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "station_site_id", null: false
    t.bigint "outlet_site_id", null: false
    t.bigint "airing_id", null: false
    t.integer "ad_row", default: -1, null: false
    t.date "day", null: false
    t.string "platform", null: false
    t.string "session_key", null: false
    t.bigint "highest_sequence", default: -1, null: false
    t.bigint "sequence_window", default: 0, null: false
    t.integer "segments", default: 0, null: false
    t.bigint "media_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["outlet_site_id", "day"], name: "index_studio_broadcast_outlet_day"
    t.index ["session_key", "channel_id", "airing_id", "ad_row", "day"], name: "index_studio_broadcast_session_context", unique: true
    t.index ["station_site_id", "day"], name: "index_studio_broadcast_station_day"
  end

  create_table "studio_carriage_agreements", force: :cascade do |t|
    t.bigint "outlet_site_id", null: false
    t.bigint "station_site_id", null: false
    t.bigint "channel_id"
    t.bigint "hosted_carriage_id"
    t.bigint "offered_by_id", null: false
    t.bigint "accepted_by_id"
    t.datetime "accepted_at"
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.jsonb "terms", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_by_id"], name: "index_studio_carriage_agreements_on_accepted_by_id"
    t.index ["channel_id"], name: "index_studio_carriage_agreements_on_channel_id"
    t.index ["hosted_carriage_id"], name: "index_studio_carriage_agreements_on_hosted_carriage_id"
    t.index ["offered_by_id"], name: "index_studio_carriage_agreements_on_offered_by_id"
    t.index ["outlet_site_id"], name: "index_studio_carriage_agreements_on_outlet_site_id"
    t.index ["station_site_id"], name: "index_studio_carriage_agreements_on_station_site_id"
    t.check_constraint "(channel_id IS NULL) <> (hosted_carriage_id IS NULL)", name: "studio_carriage_agreement_source"
  end

  create_table "studio_channel_airings", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "operator_id", null: false
    t.string "title", null: false
    t.string "relay"
    t.string "status", default: "preparing", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.jsonb "rundown", default: [], null: false
    t.jsonb "events", default: [], null: false
    t.jsonb "state", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "measurement", default: {}, null: false
    t.index ["channel_id", "starts_at"], name: "index_studio_channel_airings_on_channel_id_and_starts_at"
    t.index ["channel_id"], name: "index_studio_channel_airings_on_channel_id"
    t.index ["operator_id"], name: "index_studio_channel_airings_on_operator_id"
    t.index ["status", "starts_at"], name: "index_studio_channel_airings_on_status_and_starts_at"
  end

  create_table "studio_compute_leases", force: :cascade do |t|
    t.bigint "studio_operation_id", null: false
    t.string "tenant_key", null: false
    t.string "token", null: false
    t.string "worker", null: false
    t.datetime "expires_at", null: false
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["studio_operation_id"], name: "index_studio_compute_leases_on_studio_operation_id", unique: true
    t.index ["tenant_key", "expires_at"], name: "index_studio_compute_leases_on_tenant_key_and_expires_at"
  end

  create_table "studio_compute_pools", force: :cascade do |t|
    t.string "name", null: false
    t.index ["name"], name: "index_studio_compute_pools_on_name", unique: true
  end

  create_table "studio_hosted_carriages", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.string "status", default: "requested", null: false
    t.string "ownership"
    t.boolean "published", default: false, null: false
    t.jsonb "schedule", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "fallback_channel_id"
    t.jsonb "relay_cursor", default: {}, null: false
    t.string "observed_feed_state"
    t.index ["fallback_channel_id"], name: "index_studio_hosted_carriages_on_fallback_channel_id"
    t.index ["key"], name: "index_studio_hosted_carriages_on_key", unique: true
    t.index ["peer_id"], name: "index_studio_hosted_carriages_on_peer_id"
    t.index ["status", "published"], name: "index_studio_hosted_carriages_on_status_and_published"
  end

  create_table "studio_live_operations", force: :cascade do |t|
    t.bigint "studio_project_id", null: false
    t.bigint "production_id"
    t.string "platform", null: false
    t.string "status", default: "draft", null: false
    t.string "credential_ref"
    t.string "show_run_id"
    t.string "gatekeeper_operation_id"
    t.jsonb "response_policy", default: {}, null: false
    t.jsonb "moderation_policy", default: {}, null: false
    t.jsonb "metrics", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gatekeeper_operation_id"], name: "index_studio_live_operations_on_gatekeeper_operation_id"
    t.index ["platform"], name: "index_studio_live_operations_on_platform"
    t.index ["production_id"], name: "index_studio_live_operations_on_production_id"
    t.index ["status"], name: "index_studio_live_operations_on_status"
    t.index ["studio_project_id"], name: "index_studio_live_operations_on_studio_project_id"
  end

  create_table "studio_network_carriages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.string "status", default: "requested", null: false
    t.string "ownership"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "remote_key"
    t.string "relay_digest"
    t.index ["channel_id"], name: "index_studio_network_carriages_on_channel_id", unique: true
    t.index ["remote_key"], name: "index_studio_network_carriages_on_remote_key", unique: true
  end

  create_table "studio_operation_records", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "operation_id", null: false
    t.string "surface", null: false
    t.integer "version", null: false
    t.jsonb "body", null: false
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "owner_id"
    t.index ["owner_id"], name: "index_studio_operation_records_on_owner_id"
    t.index ["site_id", "operation_id", "surface", "version"], name: "idx_studio_operation_records_identity", unique: true
    t.check_constraint "surface::text = ANY (ARRAY['image'::character varying, 'motion'::character varying, 'both'::character varying]::text[])", name: "studio_operation_records_surface"
    t.check_constraint "version > 0", name: "studio_operation_records_positive_version"
  end

  create_table "studio_operations", force: :cascade do |t|
    t.bigint "studio_project_id", null: false
    t.bigint "production_id"
    t.bigint "studio_scene_id"
    t.string "operation_type", null: false
    t.string "provider", null: false
    t.string "capability", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "intent", default: {}, null: false
    t.jsonb "manifest", default: {}, null: false
    t.jsonb "cost_quote", default: {}, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "gatekeeper_operation_id"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gatekeeper_operation_id"], name: "index_studio_operations_on_gatekeeper_operation_id"
    t.index ["operation_type"], name: "index_studio_operations_on_operation_type"
    t.index ["production_id"], name: "index_studio_operations_on_production_id"
    t.index ["provider"], name: "index_studio_operations_on_provider"
    t.index ["status"], name: "index_studio_operations_on_status"
    t.index ["studio_project_id"], name: "index_studio_operations_on_studio_project_id"
    t.index ["studio_scene_id"], name: "index_studio_operations_on_studio_scene_id"
  end

  create_table "studio_program_clips", force: :cascade do |t|
    t.bigint "license_id", null: false
    t.bigint "site_id", null: false
    t.string "title", null: false
    t.integer "start_second", null: false
    t.integer "duration_seconds", null: false
    t.string "error_message"
    t.string "public_key", null: false
    t.datetime "withdrawn_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["license_id"], name: "index_studio_program_clips_on_license_id"
    t.index ["public_key"], name: "index_studio_program_clips_on_public_key", unique: true
    t.index ["site_id"], name: "index_studio_program_clips_on_site_id"
  end

  create_table "studio_program_distribution_handoffs", force: :cascade do |t|
    t.bigint "license_id", null: false
    t.bigint "operator_id", null: false
    t.string "platform", null: false
    t.string "partner", null: false
    t.json "territories", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.boolean "commercial", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "spec_reference"
    t.string "submission_reference"
    t.datetime "submitted_at"
    t.json "quality_checks"
    t.index ["license_id"], name: "index_studio_program_distribution_handoffs_on_license_id"
    t.index ["operator_id"], name: "index_studio_program_distribution_handoffs_on_operator_id"
  end

  create_table "studio_program_licenses", force: :cascade do |t|
    t.bigint "licensor_site_id"
    t.bigint "licensee_site_id", null: false
    t.bigint "asset_id", null: false
    t.bigint "blob_id", null: false
    t.string "title", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "offered", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "federation_key"
    t.string "originator_name"
    t.string "creative_digest"
    t.bigint "publisher_peer_id"
    t.jsonb "additional_rights", default: [], null: false
    t.bigint "parent_license_id"
    t.json "territories"
    t.json "platforms"
    t.string "web_screening_key"
    t.bigint "rights_attested_by_id"
    t.string "rights_evidence_reference"
    t.index ["federation_key"], name: "index_studio_program_licenses_on_federation_key", unique: true
    t.index ["licensee_site_id", "status", "ends_at"], name: "idx_on_licensee_site_id_status_ends_at_2441e1a5c5"
    t.index ["licensee_site_id"], name: "index_studio_program_licenses_on_licensee_site_id"
    t.index ["licensor_site_id"], name: "index_studio_program_licenses_on_licensor_site_id"
    t.index ["parent_license_id"], name: "index_studio_program_licenses_on_parent_license_id"
    t.index ["publisher_peer_id"], name: "index_studio_program_licenses_on_publisher_peer_id"
    t.index ["rights_attested_by_id"], name: "index_studio_program_licenses_on_rights_attested_by_id"
    t.index ["web_screening_key"], name: "index_studio_program_licenses_on_web_screening_key", unique: true
  end

  create_table "studio_projects", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "owner_id"
    t.bigint "site_id"
    t.boolean "is_template", default: false, null: false
    t.string "request_key"
    t.boolean "animation_workspace", default: false, null: false
    t.index ["owner_id", "request_key"], name: "index_studio_projects_on_owner_id_and_request_key", unique: true
    t.index ["owner_id"], name: "index_studio_projects_on_owner_id"
    t.index ["site_id"], name: "index_studio_projects_on_site_id"
  end

  create_table "studio_publications", force: :cascade do |t|
    t.bigint "studio_project_id", null: false
    t.bigint "production_id"
    t.bigint "artifact_id", null: false
    t.string "platform", null: false
    t.string "destination"
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_at"
    t.datetime "published_at"
    t.string "external_id"
    t.string "external_url"
    t.string "gatekeeper_operation_id"
    t.jsonb "metadata", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "request_key"
    t.index ["artifact_id"], name: "index_studio_publications_on_artifact_id"
    t.index ["platform"], name: "index_studio_publications_on_platform"
    t.index ["production_id"], name: "index_studio_publications_on_production_id"
    t.index ["scheduled_at"], name: "index_studio_publications_on_scheduled_at"
    t.index ["status"], name: "index_studio_publications_on_status"
    t.index ["studio_project_id", "request_key"], name: "idx_studio_publication_request_unique", unique: true
    t.index ["studio_project_id"], name: "index_studio_publications_on_studio_project_id"
  end

  create_table "studio_recipes", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", limit: 120, null: false
    t.integer "version", null: false
    t.jsonb "body", null: false
    t.text "source_tutorial_reference"
    t.boolean "published", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "name", "version"], name: "index_studio_recipes_on_site_id_and_name_and_version", unique: true
    t.check_constraint "version > 0", name: "studio_recipes_positive_version"
  end

  create_table "studio_remote_renders", force: :cascade do |t|
    t.bigint "peer_id", null: false
    t.bigint "studio_operation_id", null: false
    t.string "request_key", null: false
    t.string "manifest_digest", null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "enqueued_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["peer_id", "request_key"], name: "index_studio_remote_renders_on_peer_id_and_request_key", unique: true
    t.index ["peer_id"], name: "index_studio_remote_renders_on_peer_id"
    t.index ["studio_operation_id"], name: "index_studio_remote_renders_on_studio_operation_id", unique: true
  end

  create_table "studio_render_results", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.bigint "user_id", null: false
    t.bigint "operation_record_id"
    t.string "operation_id", null: false
    t.string "surface", null: false
    t.integer "version", null: false
    t.string "input_filename"
    t.string "status", default: "pending", null: false
    t.jsonb "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_record_id"], name: "index_studio_render_results_on_operation_record_id"
    t.index ["site_id", "user_id", "operation_id", "surface", "created_at"], name: "index_studio_render_results_on_run_history"
    t.index ["site_id"], name: "index_studio_render_results_on_site_id"
    t.index ["user_id"], name: "index_studio_render_results_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "studio_render_results_status_check"
  end

  create_table "studio_scene_renders", force: :cascade do |t|
    t.bigint "studio_scene_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "progress", default: 0, null: false
    t.jsonb "manifest", null: false
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "request_id"
    t.integer "scene_revision"
    t.bigint "retry_of_id"
    t.string "claim_token"
    t.datetime "lease_expires_at"
    t.string "failed_phase"
    t.index ["status", "created_at"], name: "index_studio_scene_renders_on_status_and_created_at"
    t.index ["status", "lease_expires_at"], name: "index_studio_scene_renders_on_status_and_lease_expires_at"
    t.index ["studio_scene_id", "request_id"], name: "index_studio_scene_renders_on_scene_and_request", unique: true
    t.index ["studio_scene_id"], name: "index_studio_scene_renders_on_studio_scene_id"
  end

  create_table "studio_scenes", force: :cascade do |t|
    t.bigint "studio_project_id", null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "production_id"
    t.integer "lock_version", default: 0, null: false
    t.jsonb "scene_spec"
    t.index ["production_id"], name: "index_studio_scenes_on_production_id"
    t.index ["studio_project_id"], name: "index_studio_scenes_on_studio_project_id"
  end

  create_table "studio_sponsor_package_spots", force: :cascade do |t|
    t.bigint "package_id", null: false
    t.bigint "payment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["package_id"], name: "index_studio_sponsor_package_spots_on_package_id"
    t.index ["payment_id"], name: "index_studio_sponsor_package_spots_on_payment_id", unique: true
  end

  create_table "studio_sponsor_packages", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "name", null: false
    t.string "public_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_key"], name: "index_studio_sponsor_packages_on_public_key", unique: true
    t.index ["site_id"], name: "index_studio_sponsor_packages_on_site_id"
  end

  create_table "studio_workstations", force: :cascade do |t|
    t.bigint "owner_id", null: false
    t.bigint "site_id"
    t.bigint "studio_scene_id", null: false
    t.string "session_key", null: false
    t.string "request_key", null: false
    t.string "status", default: "starting", null: false
    t.string "container_id"
    t.integer "port"
    t.datetime "expires_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "request_key"], name: "index_studio_workstations_on_owner_id_and_request_key", unique: true
    t.index ["owner_id"], name: "index_studio_workstations_on_owner_id"
    t.index ["session_key"], name: "index_studio_workstations_on_session_key", unique: true
    t.index ["site_id"], name: "index_studio_workstations_on_site_id"
    t.index ["studio_scene_id"], name: "index_studio_workstations_on_studio_scene_id"
  end

  create_table "subscription_infrastructure_entitlements", force: :cascade do |t|
    t.bigint "subscription_plan_id", null: false
    t.bigint "provisioning_profile_id"
    t.bigint "compute_policy_id"
    t.integer "node_quantity", default: 0, null: false
    t.boolean "auto_provision", default: false, null: false
    t.jsonb "feature_entitlements", default: [], null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "max_sites", default: 1, null: false
    t.index ["compute_policy_id"], name: "idx_on_compute_policy_id_870c8d7330"
    t.index ["provisioning_profile_id"], name: "idx_on_provisioning_profile_id_cda1cb21d7"
    t.index ["subscription_plan_id"], name: "idx_on_subscription_plan_id_aad2877b03"
    t.index ["subscription_plan_id"], name: "idx_subscription_infra_entitlements_plan", unique: true
  end

  create_table "supports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "susu_commitments", force: :cascade do |t|
    t.bigint "susu_membership_id", null: false
    t.bigint "susu_cycle_id"
    t.decimal "contribution_amount", precision: 12, scale: 2, null: false
    t.integer "rounds_committed", null: false
    t.decimal "remaining_amount", precision: 12, scale: 2, null: false
    t.datetime "accepted_at"
    t.string "terms_version", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["susu_cycle_id"], name: "index_susu_commitments_on_susu_cycle_id"
    t.index ["susu_membership_id"], name: "index_susu_commitments_on_susu_membership_id"
  end

  create_table "susu_contributions", force: :cascade do |t|
    t.bigint "susu_group_id", null: false
    t.bigint "user_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.integer "cycle_number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "paid_at"
    t.text "failure_message"
    t.integer "round_number", default: 1, null: false
    t.bigint "susu_round_id"
    t.bigint "susu_membership_id"
    t.datetime "next_retry_at"
    t.integer "attempt_count", default: 0, null: false
    t.index ["status"], name: "index_susu_contributions_on_status"
    t.index ["susu_group_id", "user_id", "cycle_number", "round_number"], name: "idx_susu_contributions_unique_per_round", unique: true
    t.index ["susu_group_id"], name: "index_susu_contributions_on_susu_group_id"
    t.index ["susu_membership_id"], name: "index_susu_contributions_on_susu_membership_id"
    t.index ["susu_round_id"], name: "index_susu_contributions_on_susu_round_id"
    t.index ["user_id"], name: "index_susu_contributions_on_user_id"
  end

  create_table "susu_cycles", force: :cascade do |t|
    t.bigint "susu_group_id", null: false
    t.integer "number", null: false
    t.string "status", default: "draft", null: false
    t.datetime "starts_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["susu_group_id", "number"], name: "index_susu_cycles_on_susu_group_id_and_number", unique: true
    t.index ["susu_group_id"], name: "index_susu_cycles_on_susu_group_id"
  end

  create_table "susu_groups", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "contribution_amount", precision: 10, scale: 2, null: false
    t.string "cycle_frequency", default: "monthly", null: false
    t.integer "current_cycle", default: 1, null: false
    t.integer "status", default: 0, null: false
    t.bigint "organizer_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "target_member_count", default: 2, null: false
    t.integer "current_round_number", default: 1, null: false
    t.index ["organizer_id"], name: "index_susu_groups_on_organizer_id"
  end

  create_table "susu_invitations", force: :cascade do |t|
    t.bigint "susu_group_id", null: false
    t.bigint "inviter_id", null: false
    t.string "email_address", null: false
    t.integer "payout_position", null: false
    t.string "status", default: "pending", null: false
    t.datetime "accepted_at"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_susu_invitations_on_expires_at"
    t.index ["inviter_id"], name: "index_susu_invitations_on_inviter_id"
    t.index ["status"], name: "index_susu_invitations_on_status"
    t.index ["susu_group_id", "email_address"], name: "idx_susu_invites_group_email", unique: true
    t.index ["susu_group_id"], name: "index_susu_invitations_on_susu_group_id"
  end

  create_table "susu_match_preferences", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.decimal "contribution_amount", precision: 12, scale: 2, null: false
    t.string "cycle_frequency", null: false
    t.decimal "desired_payout", precision: 12, scale: 2, null: false
    t.integer "desired_member_count", null: false
    t.string "matching_mode", default: "suggestions", null: false
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_susu_match_preferences_on_user_id"
  end

  create_table "susu_memberships", force: :cascade do |t|
    t.bigint "susu_group_id", null: false
    t.bigint "user_id", null: false
    t.integer "payout_position", null: false
    t.boolean "payout_received", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "commitment_status", default: "pending", null: false
    t.boolean "autopay_enabled", default: false, null: false
    t.datetime "joined_at"
    t.datetime "exit_requested_at"
    t.index ["susu_group_id", "payout_position"], name: "index_susu_memberships_on_susu_group_id_and_payout_position", unique: true
    t.index ["susu_group_id", "user_id"], name: "index_susu_memberships_on_susu_group_id_and_user_id", unique: true
    t.index ["susu_group_id"], name: "index_susu_memberships_on_susu_group_id"
    t.index ["user_id"], name: "index_susu_memberships_on_user_id"
  end

  create_table "susu_rounds", force: :cascade do |t|
    t.bigint "susu_cycle_id", null: false
    t.integer "number", null: false
    t.bigint "recipient_membership_id", null: false
    t.datetime "due_at"
    t.string "status", default: "scheduled", null: false
    t.decimal "expected_pot", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "collected_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "paid_out_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "dymond_bank_payout_id"
    t.index ["dymond_bank_payout_id"], name: "index_susu_rounds_on_dymond_bank_payout_id"
    t.index ["recipient_membership_id"], name: "index_susu_rounds_on_recipient_membership_id"
    t.index ["susu_cycle_id", "number"], name: "index_susu_rounds_on_susu_cycle_id_and_number", unique: true
    t.index ["susu_cycle_id"], name: "index_susu_rounds_on_susu_cycle_id"
  end

  create_table "system_jobs", force: :cascade do |t|
    t.string "name"
    t.integer "priority"
    t.bigint "job_item_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_item_id"], name: "index_system_jobs_on_job_item_id"
  end

  create_table "telnyx_esim_events", force: :cascade do |t|
    t.bigint "user_esim_id", null: false
    t.string "event_id", limit: 36, null: false
    t.datetime "created_at", null: false
    t.index ["event_id"], name: "index_telnyx_esim_events_on_event_id", unique: true
    t.index ["user_esim_id"], name: "index_telnyx_esim_events_on_user_esim_id"
  end

  create_table "user_esims", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "request_key", limit: 36, null: false
    t.string "sim_card_group_id", limit: 36, null: false
    t.string "telnyx_sim_id"
    t.string "iccid"
    t.string "lpa_activation_code"
    t.string "assigned_private_ip"
    t.string "customer_wg_peer_ip", null: false
    t.virtual "routing_table_id", type: :integer, as: "\nCASE\n    WHEN (id < 154) THEN (id + 99)\n    ELSE (id + 102)\nEND", stored: true
    t.integer "plan_limit_mb", null: false
    t.integer "initial_plan_limit_mb", null: false
    t.string "status", default: "provisioning", null: false
    t.string "carrier_status"
    t.datetime "purchase_started_at"
    t.datetime "limit_applied_at"
    t.datetime "activation_requested_at"
    t.datetime "route_installed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assigned_private_ip"], name: "index_user_esims_on_assigned_private_ip", unique: true
    t.index ["iccid"], name: "index_user_esims_on_iccid", unique: true
    t.index ["request_key"], name: "index_user_esims_on_request_key", unique: true
    t.index ["routing_table_id"], name: "index_user_esims_on_routing_table_id", unique: true
    t.index ["telnyx_sim_id"], name: "index_user_esims_on_telnyx_sim_id", unique: true
    t.index ["user_id"], name: "index_user_esims_on_user_id"
    t.check_constraint "plan_limit_mb > 0", name: "user_esim_positive_limit"
    t.check_constraint "routing_table_id >= 100", name: "user_esim_valid_table"
  end

  create_table "user_feature_entitlements", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "feature_slug", null: false
    t.string "source", default: "manual", null: false
    t.boolean "active", default: true, null: false
    t.datetime "granted_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "feature_slug"], name: "idx_user_feature_entitlements_unique", unique: true
    t.index ["user_id"], name: "index_user_feature_entitlements_on_user_id"
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
    t.string "api_token"
    t.string "lightek_email_address"
    t.string "stripe_connect_account_id"
    t.boolean "stripe_connect_details_submitted", default: false, null: false
    t.boolean "stripe_connect_payouts_enabled", default: false, null: false
    t.datetime "stripe_connect_onboarded_at"
    t.bigint "agency_id"
    t.integer "upstream_share_bps", default: 0, null: false
    t.integer "people_template_version", default: 0, null: false
    t.boolean "password_setup_required", default: false, null: false
    t.datetime "access_suspended_at"
    t.string "access_suspension_source"
    t.datetime "lightek_email_confirmed_at"
    t.datetime "staging_access_expires_at"
    t.index ["agency_id"], name: "index_users_on_agency_id"
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["lightek_email_address"], name: "index_users_on_lightek_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["stripe_connect_account_id"], name: "index_users_on_stripe_connect_account_id", unique: true
    t.check_constraint "upstream_share_bps >= 0 AND upstream_share_bps <= 10000", name: "account_upstream_share_valid"
  end

  create_table "website_template_inquiries", force: :cascade do |t|
    t.bigint "site_id", null: false
    t.string "template_key", null: false
    t.string "section_key", null: false
    t.jsonb "fields", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "growth_visit_id"
    t.bigint "sales_partner_id"
    t.index ["growth_visit_id"], name: "index_website_template_inquiries_on_growth_visit_id"
    t.index ["sales_partner_id"], name: "index_website_template_inquiries_on_sales_partner_id"
    t.index ["site_id"], name: "index_website_template_inquiries_on_site_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agency_profiles", "users"
  add_foreign_key "artifacts", "creation_jobs"
  add_foreign_key "artifacts", "studio_operations"
  add_foreign_key "channels", "shows"
  add_foreign_key "communities", "dymond_site_sites", column: "site_id"
  add_foreign_key "communities", "profiles", column: "owner_profile_id"
  add_foreign_key "compute_policies", "compute_providers", column: "fallback_provider_id"
  add_foreign_key "compute_policies", "compute_providers", column: "preferred_provider_id"
  add_foreign_key "creation_jobs", "studio_scenes"
  add_foreign_key "departments", "system_jobs"
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
  add_foreign_key "dymond_booking_bookings", "dymond_booking_resources", column: "resource_id"
  add_foreign_key "dymond_booking_event_rsvps", "dymond_booking_events", column: "event_id"
  add_foreign_key "dymond_catalog_marketplace_listings", "dymond_bank_offers", column: "offer_id"
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
  add_foreign_key "dymond_studio_storyboard_panels", "dymond_studio_storyboards", column: "storyboard_id"
  add_foreign_key "dymond_studio_text_overlays", "dymond_studio_timelines", column: "timeline_id"
  add_foreign_key "dymond_studio_timeline_clips", "dymond_studio_timeline_tracks", column: "track_id"
  add_foreign_key "dymond_studio_timeline_tracks", "dymond_studio_timelines", column: "timeline_id"
  add_foreign_key "gatekeeper_application_launches", "gatekeeper_application_templates"
  add_foreign_key "gatekeeper_application_launches", "gatekeeper_nodes"
  add_foreign_key "gatekeeper_application_launches", "provisioning_requests"
  add_foreign_key "gatekeeper_application_launches", "users", column: "owner_id"
  add_foreign_key "gatekeeper_application_launches", "users", column: "requested_by_id"
  add_foreign_key "gatekeeper_hosted_applications", "gatekeeper_nodes"
  add_foreign_key "gatekeeper_hosted_applications", "gatekeeper_operations"
  add_foreign_key "gatekeeper_hosted_applications", "gatekeeper_projects"
  add_foreign_key "gatekeeper_hosted_applications", "users", column: "owner_id"
  add_foreign_key "gatekeeper_hosted_applications", "users", column: "requested_by_id"
  add_foreign_key "gatekeeper_installations", "gatekeeper_nodes"
  add_foreign_key "gatekeeper_installations", "gatekeeper_projects"
  add_foreign_key "gatekeeper_installations", "gatekeeper_releases", column: "pinned_release_id"
  add_foreign_key "gatekeeper_installations", "users", column: "account_id"
  add_foreign_key "gatekeeper_nodes", "compute_policies"
  add_foreign_key "gatekeeper_nodes", "compute_providers"
  add_foreign_key "gatekeeper_nodes", "provisioning_profiles"
  add_foreign_key "gatekeeper_operations", "gatekeeper_nodes"
  add_foreign_key "gatekeeper_operations", "gatekeeper_projects"
  add_foreign_key "gatekeeper_projects", "gatekeeper_nodes"
  add_foreign_key "gatekeeper_rollouts", "gatekeeper_releases"
  add_foreign_key "gatekeeper_update_targets", "gatekeeper_installations"
  add_foreign_key "gatekeeper_update_targets", "gatekeeper_operations"
  add_foreign_key "gatekeeper_update_targets", "gatekeeper_rollouts"
  add_foreign_key "hosting_packages", "compute_providers"
  add_foreign_key "hosting_packages", "gatekeeper_application_templates"
  add_foreign_key "hosting_packages", "lightek_commerce_products", column: "product_id"
  add_foreign_key "lightek_accounting_audit_events", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_audit_events", "users", column: "actor_id"
  add_foreign_key "lightek_accounting_automations", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_automations", "users", column: "actor_id"
  add_foreign_key "lightek_accounting_bank_accounts", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_books", "users", column: "employer_id"
  add_foreign_key "lightek_accounting_categories", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_imports", "lightek_accounting_bank_accounts", column: "bank_account_id"
  add_foreign_key "lightek_accounting_imports", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_imports", "users", column: "actor_id"
  add_foreign_key "lightek_accounting_reconciliations", "lightek_accounting_bank_accounts", column: "bank_account_id"
  add_foreign_key "lightek_accounting_reconciliations", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_reconciliations", "users", column: "actor_id"
  add_foreign_key "lightek_accounting_rules", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_rules", "lightek_accounting_categories", column: "category_id"
  add_foreign_key "lightek_accounting_transactions", "lightek_accounting_bank_accounts", column: "bank_account_id"
  add_foreign_key "lightek_accounting_transactions", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_transactions", "lightek_accounting_categories", column: "category_id"
  add_foreign_key "lightek_accounting_transactions", "lightek_accounting_imports", column: "statement_import_id"
  add_foreign_key "lightek_accounting_transactions", "lightek_accounting_reconciliations", column: "reconciliation_id"
  add_foreign_key "lightek_accounting_workbooks", "lightek_accounting_books", column: "book_id"
  add_foreign_key "lightek_accounting_workbooks", "users", column: "actor_id"
  add_foreign_key "lightek_agency_demo_requests", "lightek_growth_visits", column: "growth_visit_id"
  add_foreign_key "lightek_agency_demo_requests", "users", column: "agency_id"
  add_foreign_key "lightek_agency_demo_settings", "users", column: "agency_id"
  add_foreign_key "lightek_agency_demos", "users", column: "agency_id"
  add_foreign_key "lightek_agency_demos", "users", column: "client_id", on_delete: :nullify
  add_foreign_key "lightek_agency_installed_packages", "users"
  add_foreign_key "lightek_agency_package_storage", "lightek_agency_installed_packages", column: "installed_package_id"
  add_foreign_key "lightek_agency_package_usages", "lightek_agency_installed_packages", column: "installed_package_id"
  add_foreign_key "lightek_agency_site_memberships", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_agency_site_memberships", "users"
  add_foreign_key "lightek_agency_site_memberships", "users", column: "granted_by_id"
  add_foreign_key "lightek_agency_trial_requests", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_agency_trial_requests", "users", column: "operator_id"
  add_foreign_key "lightek_agency_trials", "dymond_site_sites", column: "billing_site_id"
  add_foreign_key "lightek_agency_trials", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_agency_trials", "lightek_commerce_orders", column: "paid_order_id"
  add_foreign_key "lightek_agency_trials", "users", column: "operator_id"
  add_foreign_key "lightek_agency_trials", "users", column: "prospect_id"
  add_foreign_key "lightek_audience_leases", "users"
  add_foreign_key "lightek_blog_entries", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_blog_entries", "posts", on_delete: :cascade
  add_foreign_key "lightek_commerce_billing_invoices", "lightek_commerce_orders", column: "settlement_order_id"
  add_foreign_key "lightek_commerce_billing_invoices", "lightek_commerce_subscriptions", column: "subscription_id"
  add_foreign_key "lightek_commerce_collections", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_customer_segments", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_discount_uses", "lightek_commerce_discounts", column: "discount_id"
  add_foreign_key "lightek_commerce_discount_uses", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_discounts", "lightek_commerce_customer_segments", column: "customer_segment_id"
  add_foreign_key "lightek_commerce_discounts", "lightek_commerce_collections", column: "qualifying_collection_id"
  add_foreign_key "lightek_commerce_discounts", "lightek_commerce_products", column: "qualifying_product_id"
  add_foreign_key "lightek_commerce_discounts", "lightek_commerce_collections", column: "target_collection_id"
  add_foreign_key "lightek_commerce_discounts", "lightek_commerce_products", column: "target_product_id"
  add_foreign_key "lightek_commerce_discounts", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_dispute_cases", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_gift_cards", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_gift_cards", "lightek_commerce_orders", column: "purchase_order_id"
  add_foreign_key "lightek_commerce_gift_redemptions", "lightek_commerce_gift_cards", column: "gift_card_id"
  add_foreign_key "lightek_commerce_gift_redemptions", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_network_accounts", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_network_accounts", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_commerce_network_accounts", "users"
  add_foreign_key "lightek_commerce_network_sales", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_network_sales", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_commerce_network_sales", "lightek_shipping_quotes", column: "source_shipping_quote_id"
  add_foreign_key "lightek_commerce_order_items", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_order_items", "lightek_commerce_product_variants", column: "variant_id"
  add_foreign_key "lightek_commerce_order_items", "lightek_commerce_products", column: "product_id"
  add_foreign_key "lightek_commerce_orders", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_orders", "gatekeeper_application_launches"
  add_foreign_key "lightek_commerce_orders", "lightek_growth_visits", column: "growth_visit_id"
  add_foreign_key "lightek_commerce_orders", "lightek_shipping_quotes", column: "shipping_quote_id"
  add_foreign_key "lightek_commerce_orders", "users", column: "hosting_owner_id"
  add_foreign_key "lightek_commerce_product_variants", "lightek_commerce_products", column: "product_id"
  add_foreign_key "lightek_commerce_products", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_commerce_products", "hosting_packages", column: "source_hosting_package_id"
  add_foreign_key "lightek_commerce_refunds", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_revenue_allocations", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_commerce_revenue_allocations", "users", column: "beneficiary_id"
  add_foreign_key "lightek_commerce_subscriptions", "dymond_bank_subscriptions", column: "bank_subscription_id"
  add_foreign_key "lightek_commerce_subscriptions", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_communications_service_events", "lightek_commerce_billing_invoices", column: "billing_invoice_id"
  add_foreign_key "lightek_communications_service_events", "lightek_communications_services", column: "service_id"
  add_foreign_key "lightek_communications_service_events", "users", column: "operator_id"
  add_foreign_key "lightek_communications_services", "lightek_commerce_subscriptions", column: "subscription_id"
  add_foreign_key "lightek_community_engagements", "posts"
  add_foreign_key "lightek_community_engagements", "profiles"
  add_foreign_key "lightek_community_memberships", "communities"
  add_foreign_key "lightek_community_memberships", "profiles"
  add_foreign_key "lightek_compliance_monitors", "users", column: "actor_id"
  add_foreign_key "lightek_compliance_monitors", "users", column: "employer_id"
  add_foreign_key "lightek_connect_connections", "users"
  add_foreign_key "lightek_connect_events", "lightek_connect_connections", column: "connection_id"
  add_foreign_key "lightek_connect_grants", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_connect_grants", "lightek_connect_connections", column: "connection_id"
  add_foreign_key "lightek_connect_grants", "sessions", column: "authorization_session_id", on_delete: :nullify
  add_foreign_key "lightek_connect_sandboxes", "gatekeeper_nodes"
  add_foreign_key "lightek_connect_sandboxes", "users"
  add_foreign_key "lightek_discovery_channel_holds", "lightek_mail_matters", column: "matter_id"
  add_foreign_key "lightek_discovery_channel_holds", "lightek_team_channels", column: "channel_id", on_delete: :cascade
  add_foreign_key "lightek_discovery_drive_holds", "lightek_mail_matters", column: "matter_id"
  add_foreign_key "lightek_discovery_drive_holds", "lightek_shared_drives", column: "drive_id"
  add_foreign_key "lightek_experiment_assignments", "lightek_experiments", column: "experiment_id"
  add_foreign_key "lightek_experiment_outcomes", "lightek_experiment_assignments", column: "assignment_id"
  add_foreign_key "lightek_feature_flag_changes", "lightek_feature_flags", column: "flag_id"
  add_foreign_key "lightek_feature_flag_changes", "users", column: "actor_id"
  add_foreign_key "lightek_full_packages", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_full_packages", "users", column: "buyer_id"
  add_foreign_key "lightek_growth_audit_findings", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_audit_findings", "lightek_growth_website_audits", column: "website_audit_id"
  add_foreign_key "lightek_growth_audit_findings", "users", column: "resolved_by_id"
  add_foreign_key "lightek_growth_audit_fixes", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_audit_fixes", "lightek_growth_audit_findings", column: "finding_id"
  add_foreign_key "lightek_growth_audit_fixes", "users", column: "applied_by_id"
  add_foreign_key "lightek_growth_audit_fixes", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_audit_fixes", "users", column: "rolled_back_by_id"
  add_foreign_key "lightek_growth_briefs", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_briefs", "users", column: "updated_by_id"
  add_foreign_key "lightek_growth_comparison_arms", "lightek_growth_comparisons", column: "comparison_id"
  add_foreign_key "lightek_growth_comparison_arms", "lightek_growth_links", column: "link_id"
  add_foreign_key "lightek_growth_comparison_arms", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_growth_comparisons", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_comparisons", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_demo_exposures", "lightek_growth_feature_showcases", column: "showcase_id"
  add_foreign_key "lightek_growth_demo_exposures", "lightek_growth_visits", column: "visit_id"
  add_foreign_key "lightek_growth_feature_clips", "lightek_growth_feature_showcases", column: "feature_showcase_id"
  add_foreign_key "lightek_growth_feature_showcases", "dymond_site_pages", column: "page_id"
  add_foreign_key "lightek_growth_feature_showcases", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_feature_showcases", "lightek_growth_marketing_kits", column: "marketing_kit_id"
  add_foreign_key "lightek_growth_feature_showcases", "users", column: "approved_by_id"
  add_foreign_key "lightek_growth_feature_showcases", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_links", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_links", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_growth_links", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_marketing_check_ins", "lightek_growth_marketing_kits", column: "marketing_kit_id"
  add_foreign_key "lightek_growth_marketing_check_ins", "users", column: "actor_id"
  add_foreign_key "lightek_growth_marketing_executions", "lightek_growth_marketing_kits", column: "marketing_kit_id"
  add_foreign_key "lightek_growth_marketing_executions", "nevaeh_goals", column: "goal_id"
  add_foreign_key "lightek_growth_marketing_executions", "users", column: "actor_id"
  add_foreign_key "lightek_growth_marketing_kits", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_marketing_kits", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_growth_marketing_kits", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_page_metadata", "dymond_site_pages", column: "page_id", on_delete: :cascade
  add_foreign_key "lightek_growth_page_metadata", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_page_metadata", "users", column: "updated_by_id"
  add_foreign_key "lightek_growth_performance_drafts", "lightek_growth_performance_reviews", column: "review_id"
  add_foreign_key "lightek_growth_performance_drafts", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_growth_performance_drafts", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_performance_reviews", "lightek_growth_comparisons", column: "comparison_id"
  add_foreign_key "lightek_growth_performance_reviews", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_plans", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_plans", "lightek_growth_plans", column: "previous_plan_id"
  add_foreign_key "lightek_growth_plans", "users", column: "created_by_id"
  add_foreign_key "lightek_growth_steps", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_steps", "lightek_growth_plans", column: "plan_id"
  add_foreign_key "lightek_growth_steps", "users", column: "resolved_by_id"
  add_foreign_key "lightek_growth_visits", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_visits", "lightek_growth_links", column: "link_id"
  add_foreign_key "lightek_growth_website_audits", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_growth_website_audits", "users", column: "created_by_id"
  add_foreign_key "lightek_identity_connections", "users", column: "employer_id"
  add_foreign_key "lightek_identity_factors", "users"
  add_foreign_key "lightek_identity_login_attempts", "lightek_identity_connections", column: "connection_id"
  add_foreign_key "lightek_identity_login_attempts", "users"
  add_foreign_key "lightek_identity_node_bindings", "gatekeeper_nodes"
  add_foreign_key "lightek_identity_node_bindings", "lightek_identity_realms", column: "realm_id"
  add_foreign_key "lightek_identity_organization_policies", "users", column: "employer_id"
  add_foreign_key "lightek_identity_realms", "users", column: "employer_id"
  add_foreign_key "lightek_identity_resource_grants", "users", column: "employer_id"
  add_foreign_key "lightek_identity_subjects", "lightek_identity_connections", column: "connection_id"
  add_foreign_key "lightek_identity_subjects", "users"
  add_foreign_key "lightek_live_viewers", "studio_live_operations"
  add_foreign_key "lightek_live_viewers", "users"
  add_foreign_key "lightek_mail_accounts", "lightek_mail_domains", column: "domain_id"
  add_foreign_key "lightek_mail_accounts", "lightek_mail_templates", column: "auto_template_id"
  add_foreign_key "lightek_mail_accounts", "lightek_reservation_peers", column: "installation_peer_id"
  add_foreign_key "lightek_mail_accounts", "users"
  add_foreign_key "lightek_mail_auto_replies", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_calendar_history_events", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_calendar_history_previews", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_calendar_history_previews", "lightek_team_mail_migration_mailboxes", column: "team_mailbox_id"
  add_foreign_key "lightek_mail_calendar_invitations", "lightek_mail_accounts", column: "account_id", on_delete: :cascade
  add_foreign_key "lightek_mail_calendar_invitations", "lightek_mail_messages", column: "reply_message_id", on_delete: :nullify
  add_foreign_key "lightek_mail_calendar_invitations", "lightek_mail_messages", column: "source_message_id", on_delete: :nullify
  add_foreign_key "lightek_mail_contact_previews", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_contact_previews", "lightek_team_mail_migration_mailboxes", column: "team_mailbox_id"
  add_foreign_key "lightek_mail_contacts", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_customer_suspensions", "users"
  add_foreign_key "lightek_mail_discovery_events", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_discovery_events", "lightek_mail_matters", column: "matter_id"
  add_foreign_key "lightek_mail_discovery_events", "lightek_shared_drives", column: "drive_id", on_delete: :nullify
  add_foreign_key "lightek_mail_discovery_events", "lightek_team_channels", column: "channel_id", on_delete: :nullify
  add_foreign_key "lightek_mail_discovery_events", "users", column: "actor_id"
  add_foreign_key "lightek_mail_discovery_events", "users", column: "employer_id"
  add_foreign_key "lightek_mail_domains", "users"
  add_foreign_key "lightek_mail_envelopes", "action_mailbox_inbound_emails", column: "inbound_email_id", on_delete: :cascade
  add_foreign_key "lightek_mail_feedback_events", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_group_members", "lightek_mail_accounts", column: "group_id"
  add_foreign_key "lightek_mail_group_members", "lightek_mail_accounts", column: "member_id"
  add_foreign_key "lightek_mail_imports", "lightek_mail_accounts", column: "account_id", on_delete: :cascade
  add_foreign_key "lightek_mail_imports", "lightek_team_mail_migration_mailboxes", column: "team_mailbox_id"
  add_foreign_key "lightek_mail_imports", "users", column: "requested_by_id"
  add_foreign_key "lightek_mail_matter_holds", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_matter_holds", "lightek_mail_matters", column: "matter_id"
  add_foreign_key "lightek_mail_matter_reviewers", "lightek_mail_matters", column: "matter_id"
  add_foreign_key "lightek_mail_matter_reviewers", "users"
  add_foreign_key "lightek_mail_matters", "users", column: "employer_id"
  add_foreign_key "lightek_mail_messages", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_retained_messages", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_retention_rules", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_send_reservations", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_mail_send_reservations", "users"
  add_foreign_key "lightek_mail_templates", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_managed_dns_enrollments", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_managed_dns_enrollments", "users", column: "owner_id"
  add_foreign_key "lightek_managed_dns_enrollments", "users", column: "requested_by_id"
  add_foreign_key "lightek_managed_dns_enrollments", "users", column: "reviewed_by_id"
  add_foreign_key "lightek_marketing_campaigns", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_campaigns", "lightek_mail_accounts", column: "mail_account_id"
  add_foreign_key "lightek_marketing_campaigns", "lightek_marketing_media_bindings", column: "media_binding_id"
  add_foreign_key "lightek_marketing_campaigns", "users", column: "content_approved_by_id"
  add_foreign_key "lightek_marketing_contacts", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_contacts", "lightek_sales_accounts", column: "sales_account_id"
  add_foreign_key "lightek_marketing_contacts", "users", column: "sales_owner_id"
  add_foreign_key "lightek_marketing_content_variants", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_content_variants", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_marketing_content_variants", "users", column: "approved_by_id"
  add_foreign_key "lightek_marketing_content_variants", "users", column: "created_by_id"
  add_foreign_key "lightek_marketing_deliveries", "lightek_mail_messages", column: "mail_message_id"
  add_foreign_key "lightek_marketing_deliveries", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_marketing_deliveries", "lightek_marketing_contacts", column: "contact_id"
  add_foreign_key "lightek_marketing_media_bindings", "artifacts", on_delete: :nullify
  add_foreign_key "lightek_marketing_media_bindings", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_media_bindings", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_marketing_media_bindings", "users", column: "created_by_id"
  add_foreign_key "lightek_marketing_publication_slots", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_publication_slots", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_marketing_publication_slots", "lightek_marketing_social_connections", column: "connection_id"
  add_foreign_key "lightek_marketing_publication_slots", "lightek_marketing_social_posts", column: "social_post_id"
  add_foreign_key "lightek_marketing_publication_slots", "users", column: "scheduled_by_id"
  add_foreign_key "lightek_marketing_social_connections", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_marketing_social_posts", "lightek_marketing_campaigns", column: "campaign_id"
  add_foreign_key "lightek_marketing_social_posts", "lightek_marketing_social_connections", column: "connection_id"
  add_foreign_key "lightek_merchant_payout_schedules", "users", column: "merchant_id"
  add_foreign_key "lightek_messaging_conversations", "profiles", column: "created_by_profile_id"
  add_foreign_key "lightek_messaging_messages", "lightek_messaging_conversations", column: "conversation_id"
  add_foreign_key "lightek_messaging_messages", "lightek_messaging_messages", column: "reply_to_message_id"
  add_foreign_key "lightek_messaging_messages", "profiles", column: "sender_profile_id"
  add_foreign_key "lightek_messaging_participants", "lightek_messaging_conversations", column: "conversation_id"
  add_foreign_key "lightek_messaging_participants", "profiles"
  add_foreign_key "lightek_network_office_files", "lightek_reservation_peers", column: "editor_peer_id"
  add_foreign_key "lightek_network_office_files", "lightek_team_network_channels", column: "channel_id"
  add_foreign_key "lightek_office_files", "lightek_shared_drive_entries", column: "drive_entry_id"
  add_foreign_key "lightek_office_files", "lightek_team_channels", column: "channel_id"
  add_foreign_key "lightek_office_files", "users", column: "creator_id"
  add_foreign_key "lightek_office_files", "users", column: "editor_id"
  add_foreign_key "lightek_payout_connection_changes", "users"
  add_foreign_key "lightek_people_audit_events", "users", column: "actor_id"
  add_foreign_key "lightek_people_audit_events", "users", column: "employer_id"
  add_foreign_key "lightek_people_benefit_enrollments", "lightek_people_benefit_plans", column: "benefit_plan_id"
  add_foreign_key "lightek_people_benefit_enrollments", "lightek_people_employments", column: "employment_id"
  add_foreign_key "lightek_people_benefit_plans", "users", column: "employer_id"
  add_foreign_key "lightek_people_departments", "lightek_people_departments", column: "parent_id"
  add_foreign_key "lightek_people_departments", "users", column: "employer_id"
  add_foreign_key "lightek_people_employments", "lightek_people_departments", column: "department_id"
  add_foreign_key "lightek_people_employments", "lightek_people_employments", column: "manager_id"
  add_foreign_key "lightek_people_employments", "users", column: "employer_id"
  add_foreign_key "lightek_people_employments", "users", column: "worker_id"
  add_foreign_key "lightek_people_lifecycle_cases", "users", column: "completed_by_id"
  add_foreign_key "lightek_people_lifecycle_cases", "users", column: "created_by_id"
  add_foreign_key "lightek_people_lifecycle_cases", "users", column: "employer_id"
  add_foreign_key "lightek_people_lifecycle_cases", "users", column: "revoked_by_id"
  add_foreign_key "lightek_people_pay_runs", "users", column: "approved_by_id"
  add_foreign_key "lightek_people_pay_runs", "users", column: "employer_id"
  add_foreign_key "lightek_people_pay_runs", "users", column: "preparation_actor_id"
  add_foreign_key "lightek_people_pay_runs", "users", column: "prepared_by_id"
  add_foreign_key "lightek_people_pay_statements", "lightek_people_employments", column: "employment_id"
  add_foreign_key "lightek_people_pay_statements", "lightek_people_pay_runs", column: "pay_run_id"
  add_foreign_key "lightek_people_pay_statements", "users", column: "prepared_by_id"
  add_foreign_key "lightek_people_payout_destinations", "lightek_people_employments", column: "employment_id"
  add_foreign_key "lightek_people_payout_senders", "users", column: "employer_id"
  add_foreign_key "lightek_pwa_admin_events", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_pwa_admin_events", "users", column: "actor_id"
  add_foreign_key "lightek_pwa_applications", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_pwa_creator_earnings", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_pwa_creator_earnings", "lightek_pwa_creator_payments", column: "creator_payment_id"
  add_foreign_key "lightek_pwa_creator_offers", "users", column: "creator_id"
  add_foreign_key "lightek_pwa_creator_payments", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_pwa_creator_payments", "posts", on_delete: :nullify
  add_foreign_key "lightek_pwa_creator_payments", "users", column: "creator_id"
  add_foreign_key "lightek_pwa_creator_payments", "users", column: "supporter_id"
  add_foreign_key "lightek_pwa_launch_settings", "users", column: "updated_by_id"
  add_foreign_key "lightek_pwa_member_backends", "gatekeeper_application_launches", column: "launch_id"
  add_foreign_key "lightek_pwa_member_backends", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_pwa_member_backends", "lightek_pwa_shared_pools", column: "shared_pool_id"
  add_foreign_key "lightek_pwa_member_backends", "users"
  add_foreign_key "lightek_pwa_member_signup_requests", "users"
  add_foreign_key "lightek_pwa_member_tickets", "lightek_pwa_member_backends", column: "member_backend_id"
  add_foreign_key "lightek_pwa_memberships", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_pwa_memberships", "profiles"
  add_foreign_key "lightek_pwa_platform_operators", "users", column: "operator_id"
  add_foreign_key "lightek_pwa_publication_references", "posts"
  add_foreign_key "lightek_pwa_purchases", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_pwa_purchases", "users"
  add_foreign_key "lightek_pwa_revenue_periods", "lightek_pwa_purchases", column: "purchase_id"
  add_foreign_key "lightek_pwa_shared_pools", "gatekeeper_application_launches", column: "launch_id"
  add_foreign_key "lightek_pwa_shared_pools", "gatekeeper_application_launches", column: "standby_launch_id"
  add_foreign_key "lightek_pwa_shared_pools", "gatekeeper_nodes", column: "node_id"
  add_foreign_key "lightek_pwa_shared_pools", "users", column: "operator_id"
  add_foreign_key "lightek_pwa_surface_modules", "lightek_pwa_surfaces", column: "surface_id"
  add_foreign_key "lightek_pwa_view_batches", "users", column: "recorded_by_id"
  add_foreign_key "lightek_pwa_view_earnings", "lightek_pwa_view_batches", column: "view_batch_id"
  add_foreign_key "lightek_pwa_view_earnings", "users"
  add_foreign_key "lightek_pwa_youtube_revenues", "users"
  add_foreign_key "lightek_pwa_youtube_revenues", "users", column: "recorded_by_id"
  add_foreign_key "lightek_pwa_youtube_uploads", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_pwa_youtube_uploads", "posts", on_delete: :nullify
  add_foreign_key "lightek_pwa_youtube_uploads", "users"
  add_foreign_key "lightek_reservation_blackouts", "lightek_reservation_resources", column: "resource_id"
  add_foreign_key "lightek_reservation_changes", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_reservation_changes", "lightek_reservation_resources", column: "target_resource_id"
  add_foreign_key "lightek_reservation_changes", "lightek_reservations", column: "reservation_id"
  add_foreign_key "lightek_reservation_intents", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_reservation_intents", "lightek_reservation_resources", column: "resource_id"
  add_foreign_key "lightek_reservation_intents", "lightek_reservations", column: "reservation_id"
  add_foreign_key "lightek_reservation_intents", "users", column: "customer_id"
  add_foreign_key "lightek_reservation_peers", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_reservation_peers", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_reservation_peers", "lightek_pwa_member_backends", column: "member_backend_id"
  add_foreign_key "lightek_reservation_peers", "users", column: "merchant_id"
  add_foreign_key "lightek_reservation_resources", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_reservation_resources", "lightek_commerce_products", column: "product_id"
  add_foreign_key "lightek_reservation_resources", "lightek_reservation_resources", column: "source_resource_id"
  add_foreign_key "lightek_reservations", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_reservations", "lightek_reservation_resources", column: "resource_id"
  add_foreign_key "lightek_reservations", "users", column: "customer_id"
  add_foreign_key "lightek_sales_accounts", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_accounts", "users", column: "owner_id"
  add_foreign_key "lightek_sales_activities", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_activities", "users", column: "actor_id"
  add_foreign_key "lightek_sales_commission_payouts", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_sales_commission_payouts", "lightek_sales_referrals", column: "referral_id"
  add_foreign_key "lightek_sales_commission_payouts", "users", column: "owner_id"
  add_foreign_key "lightek_sales_commission_payouts", "users", column: "released_by_id"
  add_foreign_key "lightek_sales_intake_entries", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_intake_entries", "lightek_sales_leads", column: "lead_id"
  add_foreign_key "lightek_sales_intake_entries", "users", column: "created_by_id"
  add_foreign_key "lightek_sales_intake_entries", "users", column: "processed_by_id"
  add_foreign_key "lightek_sales_intake_entries", "website_template_inquiries", column: "inquiry_id"
  add_foreign_key "lightek_sales_intake_rules", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_leads", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_leads", "lightek_growth_visits", column: "growth_visit_id"
  add_foreign_key "lightek_sales_leads", "lightek_sales_opportunities", column: "opportunity_id"
  add_foreign_key "lightek_sales_leads", "users", column: "owner_id"
  add_foreign_key "lightek_sales_opportunities", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_opportunities", "lightek_growth_visits", column: "growth_visit_id"
  add_foreign_key "lightek_sales_opportunities", "lightek_marketing_contacts", column: "contact_id"
  add_foreign_key "lightek_sales_opportunities", "lightek_sales_accounts", column: "account_id"
  add_foreign_key "lightek_sales_opportunities", "users", column: "owner_id"
  add_foreign_key "lightek_sales_partners", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_partners", "lightek_commerce_products", column: "product_id"
  add_foreign_key "lightek_sales_partners", "users", column: "payout_invited_by_id"
  add_foreign_key "lightek_sales_partners", "users", column: "payout_user_id"
  add_foreign_key "lightek_sales_prospecting_cadences", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_quotes", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_quotes", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_sales_quotes", "lightek_sales_opportunities", column: "opportunity_id"
  add_foreign_key "lightek_sales_quotes", "users", column: "accepted_by_id"
  add_foreign_key "lightek_sales_quotes", "users", column: "created_by_id"
  add_foreign_key "lightek_sales_referrals", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_sales_referrals", "lightek_sales_leads", column: "lead_id"
  add_foreign_key "lightek_sales_referrals", "lightek_sales_partners", column: "partner_id"
  add_foreign_key "lightek_sales_referrals", "users", column: "recorded_by_id"
  add_foreign_key "lightek_sales_routing_rules", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_routing_rules", "users", column: "owner_id"
  add_foreign_key "lightek_sales_social_prospects", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_social_prospects", "lightek_sales_leads", column: "lead_id"
  add_foreign_key "lightek_sales_social_prospects", "users", column: "contacted_by_id"
  add_foreign_key "lightek_sales_social_prospects", "users", column: "saved_by_id"
  add_foreign_key "lightek_sales_tasks", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_sales_tasks", "users", column: "completed_by_id"
  add_foreign_key "lightek_sales_tasks", "users", column: "created_by_id"
  add_foreign_key "lightek_sales_tasks", "users", column: "owner_id"
  add_foreign_key "lightek_session_members", "lightek_reservations", column: "reservation_id"
  add_foreign_key "lightek_session_members", "lightek_session_rooms", column: "room_id"
  add_foreign_key "lightek_session_members", "users"
  add_foreign_key "lightek_session_rooms", "lightek_reservation_resources", column: "resource_id"
  add_foreign_key "lightek_session_rooms", "users", column: "host_user_id"
  add_foreign_key "lightek_shared_calendars", "users", column: "employer_id"
  add_foreign_key "lightek_shared_drive_entries", "lightek_shared_drive_entries", column: "parent_id"
  add_foreign_key "lightek_shared_drive_entries", "lightek_shared_drives", column: "drive_id"
  add_foreign_key "lightek_shared_drive_entries", "users", column: "creator_id"
  add_foreign_key "lightek_shared_drive_import_receipts", "lightek_shared_drive_entries", column: "entry_id", on_delete: :nullify
  add_foreign_key "lightek_shared_drive_import_receipts", "lightek_shared_drives", column: "drive_id"
  add_foreign_key "lightek_shared_drive_imports", "lightek_shared_drive_entries", column: "folder_id"
  add_foreign_key "lightek_shared_drive_imports", "lightek_shared_drives", column: "drive_id"
  add_foreign_key "lightek_shared_drive_imports", "lightek_team_mail_migrations", column: "team_migration_id"
  add_foreign_key "lightek_shared_drive_imports", "users", column: "actor_id"
  add_foreign_key "lightek_shared_drive_members", "lightek_shared_drives", column: "drive_id"
  add_foreign_key "lightek_shared_drive_members", "users"
  add_foreign_key "lightek_shared_drives", "users", column: "employer_id"
  add_foreign_key "lightek_shared_event_guests", "lightek_shared_events", column: "event_id"
  add_foreign_key "lightek_shared_event_guests", "users"
  add_foreign_key "lightek_shared_events", "lightek_session_rooms", column: "session_room_id"
  add_foreign_key "lightek_shared_events", "lightek_shared_calendars", column: "calendar_id"
  add_foreign_key "lightek_shared_events", "users", column: "organizer_id"
  add_foreign_key "lightek_shared_external_invitations", "lightek_mail_accounts", column: "mailbox_id"
  add_foreign_key "lightek_shared_external_invitations", "lightek_mail_messages", column: "message_id", on_delete: :nullify
  add_foreign_key "lightek_shared_external_invitations", "lightek_shared_events", column: "event_id", on_delete: :cascade
  add_foreign_key "lightek_shipping_profiles", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_shipping_quotes", "dymond_site_sites", column: "site_id"
  add_foreign_key "lightek_shipping_quotes", "lightek_commerce_orders", column: "purchase_order_id"
  add_foreign_key "lightek_shipping_shipments", "lightek_shipping_quotes", column: "quote_id"
  add_foreign_key "lightek_social_blocks", "profiles", column: "blocked_profile_id"
  add_foreign_key "lightek_social_blocks", "profiles", column: "blocker_profile_id"
  add_foreign_key "lightek_social_circle_memberships", "lightek_social_circles", column: "circle_id"
  add_foreign_key "lightek_social_circle_memberships", "profiles"
  add_foreign_key "lightek_social_circles", "profiles", column: "owner_profile_id"
  add_foreign_key "lightek_social_connection_opportunities", "profiles"
  add_foreign_key "lightek_social_connection_opportunities", "profiles", column: "related_profile_id"
  add_foreign_key "lightek_social_follows", "profiles", column: "followed_profile_id"
  add_foreign_key "lightek_social_follows", "profiles", column: "follower_profile_id"
  add_foreign_key "lightek_social_friendships", "profiles", column: "addressee_profile_id"
  add_foreign_key "lightek_social_friendships", "profiles", column: "requester_profile_id"
  add_foreign_key "lightek_social_relationship_events", "profiles", column: "actor_profile_id"
  add_foreign_key "lightek_social_relationship_events", "profiles", column: "target_profile_id"
  add_foreign_key "lightek_social_relationship_strengths", "profiles", column: "profile_a_id"
  add_foreign_key "lightek_social_relationship_strengths", "profiles", column: "profile_b_id"
  add_foreign_key "lightek_social_top_people", "profiles"
  add_foreign_key "lightek_social_top_people", "profiles", column: "person_id"
  add_foreign_key "lightek_team_channels", "users", column: "creator_id"
  add_foreign_key "lightek_team_channels", "users", column: "employer_id"
  add_foreign_key "lightek_team_mail_migration_mailboxes", "lightek_mail_accounts", column: "account_id"
  add_foreign_key "lightek_team_mail_migration_mailboxes", "lightek_team_mail_migrations", column: "migration_id"
  add_foreign_key "lightek_team_mail_migration_mailboxes", "users", column: "mailbox_user_id"
  add_foreign_key "lightek_team_mail_migrations", "users", column: "employer_id"
  add_foreign_key "lightek_team_memberships", "lightek_team_channels", column: "channel_id"
  add_foreign_key "lightek_team_memberships", "users"
  add_foreign_key "lightek_team_messages", "lightek_team_channels", column: "channel_id"
  add_foreign_key "lightek_team_messages", "lightek_team_messages", column: "reply_to_id"
  add_foreign_key "lightek_team_messages", "users", column: "author_id"
  add_foreign_key "lightek_team_messages", "users", column: "organization_id"
  add_foreign_key "lightek_team_network_channels", "lightek_reservation_peers", column: "host_peer_id"
  add_foreign_key "lightek_team_network_channels", "lightek_reservation_peers", column: "partner_peer_id"
  add_foreign_key "lightek_team_network_members", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_team_network_members", "lightek_team_network_channels", column: "channel_id"
  add_foreign_key "lightek_team_network_messages", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_team_network_messages", "lightek_team_network_channels", column: "channel_id"
  add_foreign_key "lightek_team_partner_memberships", "lightek_team_partnerships", column: "partnership_id"
  add_foreign_key "lightek_team_partner_memberships", "users"
  add_foreign_key "lightek_team_partnerships", "lightek_team_channels", column: "channel_id"
  add_foreign_key "lightek_team_partnerships", "users", column: "partner_id"
  add_foreign_key "lightek_vault_audit_events", "lightek_vault_secrets", column: "secret_id"
  add_foreign_key "lightek_voice_add_ons", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "lightek_voice_add_ons", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "lightek_voice_carrier_operations", "lightek_communications_services", column: "service_id"
  add_foreign_key "lightek_voice_carrier_operations", "users", column: "operator_id"
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
  add_foreign_key "nevaeh_agenda_items", "users"
  add_foreign_key "nevaeh_agent_runs", "nevaeh_agent_workers"
  add_foreign_key "nevaeh_agent_runs", "nevaeh_os_actions"
  add_foreign_key "nevaeh_agent_runs", "users", column: "actor_id"
  add_foreign_key "nevaeh_agent_workers", "nevaeh_os_agents"
  add_foreign_key "nevaeh_agent_workers", "users"
  add_foreign_key "nevaeh_application_adapters", "users"
  add_foreign_key "nevaeh_calendar_invitees", "lightek_mail_accounts", column: "mailbox_id"
  add_foreign_key "nevaeh_calendar_invitees", "lightek_mail_messages", column: "message_id"
  add_foreign_key "nevaeh_calendar_invitees", "nevaeh_agenda_items", column: "agenda_item_id"
  add_foreign_key "nevaeh_construction_releases", "nevaeh_constructions"
  add_foreign_key "nevaeh_constructions", "nevaeh_construction_releases", column: "active_release_id"
  add_foreign_key "nevaeh_constructions", "users", column: "creator_id"
  add_foreign_key "nevaeh_conversation_turns", "nevaeh_conversations"
  add_foreign_key "nevaeh_conversations", "nevaeh_language_models"
  add_foreign_key "nevaeh_conversations", "users"
  add_foreign_key "nevaeh_dcp_deliveries", "nevaeh_executive_cases", column: "executive_case_id"
  add_foreign_key "nevaeh_dcp_deliveries", "users", column: "recipient_id"
  add_foreign_key "nevaeh_executive_cases", "lightek_mail_messages", column: "delivery_message_id"
  add_foreign_key "nevaeh_executive_cases", "users", column: "assignee_id"
  add_foreign_key "nevaeh_executive_cases", "users", column: "owner_id"
  add_foreign_key "nevaeh_executive_cases", "users", column: "reviewer_id"
  add_foreign_key "nevaeh_executive_phone_routes", "users", column: "assignee_id"
  add_foreign_key "nevaeh_executive_phone_routes", "users", column: "owner_id"
  add_foreign_key "nevaeh_goal_steps", "nevaeh_agent_runs"
  add_foreign_key "nevaeh_goal_steps", "nevaeh_goals"
  add_foreign_key "nevaeh_goal_steps", "nevaeh_os_agents"
  add_foreign_key "nevaeh_goals", "users"
  add_foreign_key "nevaeh_intelligences", "nevaeh_capabilities"
  add_foreign_key "nevaeh_islamic_passages", "nevaeh_islamic_sources"
  add_foreign_key "nevaeh_islamic_sources", "users", column: "creator_id"
  add_foreign_key "nevaeh_islamic_sources", "users", column: "reviewer_id"
  add_foreign_key "nevaeh_language_bindings", "nevaeh_manual_builds"
  add_foreign_key "nevaeh_language_bindings", "users", column: "creator_id"
  add_foreign_key "nevaeh_language_checkpoints", "nevaeh_language_models"
  add_foreign_key "nevaeh_language_checkpoints", "nevaeh_training_runs"
  add_foreign_key "nevaeh_language_models", "nevaeh_language_checkpoints", column: "active_checkpoint_id"
  add_foreign_key "nevaeh_learning_plans", "nevaeh_language_models", column: "language_model_id"
  add_foreign_key "nevaeh_learning_plans", "nevaeh_manual_builds"
  add_foreign_key "nevaeh_learning_plans", "nevaeh_training_runs", column: "active_training_run_id"
  add_foreign_key "nevaeh_learning_plans", "users", column: "actor_id"
  add_foreign_key "nevaeh_manual_builds", "users", column: "creator_id"
  add_foreign_key "nevaeh_onboarding_cases", "lightek_agency_trials", column: "trial_id"
  add_foreign_key "nevaeh_onboarding_cases", "lightek_commerce_orders", column: "order_id"
  add_foreign_key "nevaeh_onboarding_cases", "nevaeh_onboarding_playbooks", column: "playbook_id"
  add_foreign_key "nevaeh_onboarding_cases", "users", column: "operator_id"
  add_foreign_key "nevaeh_onboarding_playbooks", "nevaeh_onboarding_playbooks", column: "parent_id"
  add_foreign_key "nevaeh_onboarding_playbooks", "users", column: "operator_id"
  add_foreign_key "nevaeh_os_actions", "users"
  add_foreign_key "nevaeh_os_agents", "users"
  add_foreign_key "nevaeh_os_consents", "users"
  add_foreign_key "nevaeh_os_memories", "users"
  add_foreign_key "nevaeh_os_sources", "users"
  add_foreign_key "nevaeh_resolution_observations", "nevaeh_resolution_playbooks", column: "playbook_id"
  add_foreign_key "nevaeh_resolution_observations", "users", column: "operator_id"
  add_foreign_key "nevaeh_resolution_playbooks", "nevaeh_resolution_playbooks", column: "parent_id"
  add_foreign_key "nevaeh_resolution_playbooks", "users", column: "operator_id"
  add_foreign_key "nevaeh_speech_segments", "nevaeh_speeches"
  add_foreign_key "nevaeh_speeches", "users"
  add_foreign_key "nevaeh_study_routines", "nevaeh_islamic_sources", column: "source_id"
  add_foreign_key "nevaeh_study_routines", "nevaeh_language_models", column: "language_model_id"
  add_foreign_key "nevaeh_study_routines", "users", column: "creator_id"
  add_foreign_key "nevaeh_study_sessions", "nevaeh_study_routines"
  add_foreign_key "nevaeh_study_sessions", "nevaeh_training_runs"
  add_foreign_key "nevaeh_task_dialogues", "nevaeh_goals"
  add_foreign_key "nevaeh_task_dialogues", "nevaeh_os_actions"
  add_foreign_key "nevaeh_task_dialogues", "users"
  add_foreign_key "nevaeh_task_examples", "nevaeh_task_dialogues"
  add_foreign_key "nevaeh_task_examples", "users"
  add_foreign_key "nevaeh_task_turns", "nevaeh_task_dialogues"
  add_foreign_key "nevaeh_training_datasets", "users", column: "creator_id"
  add_foreign_key "nevaeh_training_runs", "nevaeh_language_models"
  add_foreign_key "nevaeh_training_runs", "nevaeh_training_datasets"
  add_foreign_key "nevaeh_training_runs", "users", column: "actor_id"
  add_foreign_key "nevaeh_travel_bookings", "nevaeh_executive_cases", column: "executive_case_id"
  add_foreign_key "nevaeh_watch_events", "nevaeh_agent_runs"
  add_foreign_key "nevaeh_watch_events", "nevaeh_watchers"
  add_foreign_key "nevaeh_watchers", "nevaeh_os_agents"
  add_foreign_key "nevaeh_watchers", "users"
  add_foreign_key "nevaeh_worker_report_reviews", "nevaeh_worker_reports"
  add_foreign_key "nevaeh_worker_report_reviews", "users"
  add_foreign_key "nevaeh_worker_reports", "nevaeh_agent_runs"
  add_foreign_key "nevaeh_worker_reports", "nevaeh_os_agents"
  add_foreign_key "nevaeh_worker_reports", "users"
  add_foreign_key "nevaeh_workflow_runs", "nevaeh_workflows"
  add_foreign_key "nevaeh_workflow_runs", "users", column: "actor_id"
  add_foreign_key "nevaeh_workflows", "users", column: "creator_id"
  add_foreign_key "nevaeh_workspace_preferences", "users"
  add_foreign_key "nevaeh_workspaces", "users"
  add_foreign_key "nevaeh_writing_profiles", "nevaeh_inference_models", column: "inference_model_id"
  add_foreign_key "nevaeh_writing_profiles", "nevaeh_language_models", column: "language_model_id"
  add_foreign_key "nevaehs", "users"
  add_foreign_key "posts", "communities"
  add_foreign_key "posts", "dymond_site_sites", column: "site_id"
  add_foreign_key "posts", "posts", column: "parent_id"
  add_foreign_key "posts", "users"
  add_foreign_key "productions", "studio_projects"
  add_foreign_key "profile_sections", "profiles"
  add_foreign_key "profile_visits", "profiles"
  add_foreign_key "profile_visits", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "provisioning_requests", "compute_policies"
  add_foreign_key "provisioning_requests", "compute_providers"
  add_foreign_key "provisioning_requests", "dymond_bank_subscription_plans", column: "subscription_plan_id"
  add_foreign_key "provisioning_requests", "dymond_bank_subscriptions", column: "subscription_id"
  add_foreign_key "provisioning_requests", "gatekeeper_nodes"
  add_foreign_key "provisioning_requests", "gatekeeper_operations"
  add_foreign_key "provisioning_requests", "provisioning_profiles"
  add_foreign_key "provisioning_requests", "subscription_infrastructure_entitlements"
  add_foreign_key "release_assurance_assignments", "release_assurance_environments", column: "environment_id"
  add_foreign_key "release_assurance_assignments", "release_assurance_testers", column: "tester_id"
  add_foreign_key "release_assurance_candidates", "users", column: "operator_id"
  add_foreign_key "release_assurance_candidates", "users", column: "promotion_approver_id"
  add_foreign_key "release_assurance_defects", "release_assurance_candidates", column: "candidate_id"
  add_foreign_key "release_assurance_defects", "release_assurance_runs", column: "retest_id"
  add_foreign_key "release_assurance_defects", "release_assurance_runs", column: "run_id"
  add_foreign_key "release_assurance_environments", "gatekeeper_operations", column: "deployment_operation_id"
  add_foreign_key "release_assurance_environments", "provisioning_requests"
  add_foreign_key "release_assurance_environments", "release_assurance_candidates", column: "candidate_id"
  add_foreign_key "release_assurance_runs", "release_assurance_assignments", column: "assignment_id"
  add_foreign_key "release_assurance_runs", "release_assurance_candidates", column: "candidate_id"
  add_foreign_key "release_assurance_runs", "release_assurance_environments", column: "environment_id"
  add_foreign_key "release_assurance_testers", "users", column: "operator_id"
  add_foreign_key "release_assurance_workflows", "release_assurance_candidates", column: "candidate_id"
  add_foreign_key "release_assurance_workflows", "release_assurance_environments", column: "environment_id"
  add_foreign_key "scene_objects", "studio_scenes"
  add_foreign_key "sessions", "lightek_identity_connections", column: "identity_connection_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "shows", "episodes"
  add_foreign_key "studio_ad_campaigns", "studio_ad_networks", column: "network_id"
  add_foreign_key "studio_ad_memberships", "dymond_site_sites", column: "station_site_id"
  add_foreign_key "studio_ad_memberships", "studio_ad_networks", column: "network_id"
  add_foreign_key "studio_ad_networks", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_ad_networks", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "studio_ad_payments", "studio_ad_placements", column: "placement_id"
  add_foreign_key "studio_ad_payouts", "studio_ad_payments", column: "payment_id"
  add_foreign_key "studio_ad_payouts", "users", column: "recipient_id"
  add_foreign_key "studio_ad_placements", "dymond_site_sites", column: "station_site_id"
  add_foreign_key "studio_ad_placements", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "studio_ad_placements", "studio_ad_campaigns", column: "campaign_id"
  add_foreign_key "studio_animation_previews", "studio_assets"
  add_foreign_key "studio_assets", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_assets", "studio_projects"
  add_foreign_key "studio_assets", "users", column: "owner_id"
  add_foreign_key "studio_broadcast_applications", "dymond_site_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "studio_broadcast_channels", "dymond_site_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "studio_broadcast_contract_evidence", "studio_broadcast_contract_versions", column: "version_id"
  add_foreign_key "studio_broadcast_contract_evidence", "users", column: "recorded_by_id"
  add_foreign_key "studio_broadcast_contract_signatures", "studio_broadcast_contract_versions", column: "version_id"
  add_foreign_key "studio_broadcast_contract_signatures", "users", column: "signer_id"
  add_foreign_key "studio_broadcast_contract_versions", "studio_broadcast_contracts", column: "contract_id"
  add_foreign_key "studio_broadcast_contract_versions", "users", column: "offered_by_id"
  add_foreign_key "studio_broadcast_contracts", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_broadcast_contracts", "studio_carriage_agreements", column: "carriage_agreement_id"
  add_foreign_key "studio_broadcast_contracts", "studio_sponsor_packages", column: "sponsor_package_id"
  add_foreign_key "studio_broadcast_contracts", "users", column: "counterparty_id"
  add_foreign_key "studio_broadcast_feed_incidents", "studio_hosted_carriages", column: "hosted_carriage_id", on_delete: :cascade
  add_foreign_key "studio_broadcast_operating_plans", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_broadcast_operating_plans", "lightek_people_departments", column: "department_id"
  add_foreign_key "studio_broadcast_operating_plans", "studio_broadcast_channels", column: "channel_id"
  add_foreign_key "studio_broadcast_operating_plans", "users", column: "owner_id"
  add_foreign_key "studio_broadcast_programs", "posts", on_delete: :cascade
  add_foreign_key "studio_broadcast_programs", "studio_broadcast_channels", column: "channel_id", on_delete: :cascade
  add_foreign_key "studio_broadcast_report_archives", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_carriage_agreements", "dymond_site_sites", column: "outlet_site_id"
  add_foreign_key "studio_carriage_agreements", "dymond_site_sites", column: "station_site_id"
  add_foreign_key "studio_carriage_agreements", "studio_broadcast_channels", column: "channel_id"
  add_foreign_key "studio_carriage_agreements", "studio_hosted_carriages", column: "hosted_carriage_id"
  add_foreign_key "studio_carriage_agreements", "users", column: "accepted_by_id"
  add_foreign_key "studio_carriage_agreements", "users", column: "offered_by_id"
  add_foreign_key "studio_channel_airings", "studio_broadcast_channels", column: "channel_id", on_delete: :cascade
  add_foreign_key "studio_channel_airings", "users", column: "operator_id", on_delete: :cascade
  add_foreign_key "studio_compute_leases", "studio_operations"
  add_foreign_key "studio_hosted_carriages", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "studio_hosted_carriages", "studio_broadcast_channels", column: "fallback_channel_id", on_delete: :nullify
  add_foreign_key "studio_live_operations", "productions"
  add_foreign_key "studio_live_operations", "studio_projects"
  add_foreign_key "studio_network_carriages", "studio_broadcast_channels", column: "channel_id", on_delete: :cascade
  add_foreign_key "studio_operation_records", "dymond_site_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "studio_operation_records", "users", column: "owner_id", on_delete: :nullify
  add_foreign_key "studio_operations", "productions"
  add_foreign_key "studio_operations", "studio_projects"
  add_foreign_key "studio_operations", "studio_scenes"
  add_foreign_key "studio_program_clips", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_program_clips", "studio_program_licenses", column: "license_id"
  add_foreign_key "studio_program_distribution_handoffs", "studio_program_licenses", column: "license_id"
  add_foreign_key "studio_program_distribution_handoffs", "users", column: "operator_id"
  add_foreign_key "studio_program_licenses", "dymond_site_sites", column: "licensee_site_id"
  add_foreign_key "studio_program_licenses", "dymond_site_sites", column: "licensor_site_id"
  add_foreign_key "studio_program_licenses", "lightek_reservation_peers", column: "publisher_peer_id"
  add_foreign_key "studio_program_licenses", "studio_program_licenses", column: "parent_license_id"
  add_foreign_key "studio_program_licenses", "users", column: "rights_attested_by_id"
  add_foreign_key "studio_projects", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_projects", "users", column: "owner_id"
  add_foreign_key "studio_publications", "artifacts"
  add_foreign_key "studio_publications", "productions"
  add_foreign_key "studio_publications", "studio_projects"
  add_foreign_key "studio_recipes", "dymond_site_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "studio_remote_renders", "lightek_reservation_peers", column: "peer_id"
  add_foreign_key "studio_remote_renders", "studio_operations"
  add_foreign_key "studio_render_results", "dymond_site_sites", column: "site_id", on_delete: :cascade
  add_foreign_key "studio_render_results", "studio_operation_records", column: "operation_record_id", on_delete: :nullify
  add_foreign_key "studio_render_results", "users", on_delete: :cascade
  add_foreign_key "studio_scene_renders", "studio_scenes"
  add_foreign_key "studio_scenes", "productions"
  add_foreign_key "studio_scenes", "studio_projects"
  add_foreign_key "studio_sponsor_package_spots", "studio_ad_payments", column: "payment_id"
  add_foreign_key "studio_sponsor_package_spots", "studio_sponsor_packages", column: "package_id"
  add_foreign_key "studio_sponsor_packages", "dymond_site_sites", column: "site_id"
  add_foreign_key "studio_workstations", "studio_scenes"
  add_foreign_key "studio_workstations", "users", column: "owner_id"
  add_foreign_key "subscription_infrastructure_entitlements", "compute_policies"
  add_foreign_key "subscription_infrastructure_entitlements", "dymond_bank_subscription_plans", column: "subscription_plan_id"
  add_foreign_key "subscription_infrastructure_entitlements", "provisioning_profiles"
  add_foreign_key "susu_commitments", "susu_cycles"
  add_foreign_key "susu_commitments", "susu_memberships"
  add_foreign_key "susu_contributions", "susu_groups"
  add_foreign_key "susu_contributions", "susu_memberships"
  add_foreign_key "susu_contributions", "susu_rounds"
  add_foreign_key "susu_contributions", "users"
  add_foreign_key "susu_cycles", "susu_groups"
  add_foreign_key "susu_groups", "users", column: "organizer_id"
  add_foreign_key "susu_invitations", "susu_groups"
  add_foreign_key "susu_invitations", "users", column: "inviter_id"
  add_foreign_key "susu_match_preferences", "users"
  add_foreign_key "susu_memberships", "susu_groups"
  add_foreign_key "susu_memberships", "users"
  add_foreign_key "susu_rounds", "susu_cycles"
  add_foreign_key "susu_rounds", "susu_memberships", column: "recipient_membership_id"
  add_foreign_key "system_jobs", "job_items"
  add_foreign_key "telnyx_esim_events", "user_esims", on_delete: :cascade
  add_foreign_key "user_esims", "users"
  add_foreign_key "user_feature_entitlements", "users"
  add_foreign_key "users", "users", column: "agency_id"
  add_foreign_key "website_template_inquiries", "dymond_site_sites", column: "site_id"
  add_foreign_key "website_template_inquiries", "lightek_growth_visits", column: "growth_visit_id"
  add_foreign_key "website_template_inquiries", "lightek_sales_partners", column: "sales_partner_id"
end
