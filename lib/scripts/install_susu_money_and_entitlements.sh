#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/susu_money_entitlements_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

for f in app/models/user.rb app/models/susu_membership.rb app/models/susu_round.rb app/controllers/susu_groups_controller.rb app/views/susu_groups/show.html.erb config/routes.rb; do
  backup "$f"
done

mkdir -p app/models app/services/dymond_bank app/services/susu app/controllers app/views/susu_payout_accounts db/migrate lib/tasks

MIGRATION="db/migrate/${STAMP}_add_susu_entitlements_and_connect_payouts.rb"
cat > "$MIGRATION" <<'RUBY'
class AddSusuEntitlementsAndConnectPayouts < ActiveRecord::Migration[8.0]
  def change
    create_table :user_feature_entitlements do |t|
      t.references :user, null: false, foreign_key: true
      t.string :feature_slug, null: false
      t.string :source, null: false, default: "manual"
      t.boolean :active, null: false, default: true
      t.datetime :granted_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :user_feature_entitlements, [:user_id, :feature_slug], unique: true,
              name: "idx_user_feature_entitlements_unique"

    add_column :users, :stripe_connect_account_id, :string
    add_column :users, :stripe_connect_details_submitted, :boolean, null: false, default: false
    add_column :users, :stripe_connect_payouts_enabled, :boolean, null: false, default: false
    add_column :users, :stripe_connect_onboarded_at, :datetime
    add_index :users, :stripe_connect_account_id, unique: true

    add_column :susu_rounds, :dymond_bank_payout_id, :bigint
    add_index :susu_rounds, :dymond_bank_payout_id
  end
end
RUBY

cat > app/models/user_feature_entitlement.rb <<'RUBY'
class UserFeatureEntitlement < ApplicationRecord
  belongs_to :user
  validates :feature_slug, presence: true, uniqueness: { scope: :user_id }
  validates :source, presence: true
  scope :active, -> { where(active: true) }

  def revoke!
    update!(active: false, revoked_at: Time.current)
  end
end
RUBY

python3 <<'PY'
from pathlib import Path
import re

path = Path("app/models/user.rb")
src = path.read_text()

anchor = '  has_many :susu_contributions, dependent: :destroy\n'
assoc = '''  has_many :feature_entitlements,
           class_name: "UserFeatureEntitlement",
           dependent: :destroy

'''
if "has_many :feature_entitlements" not in src:
    if anchor not in src:
        raise SystemExit("ERROR: User association anchor not found")
    src = src.replace(anchor, anchor + "\n" + assoc, 1)

pattern = re.compile(
    r'  # ── DymondDash role gating .*?\n'
    r'  def can_access_feature\?\(feature_slug\).*?'
    r'  end\n\n',
    re.S
)
replacement = '''  # ── DymondDash product entitlements ────────────────────────────────────────
  def can_access_feature?(feature_slug)
    return true if employee? || admin?

    feature_entitlements.active.exists?(feature_slug: feature_slug.to_s)
  end

  def grant_feature!(feature_slug, source: "manual")
    entitlement = feature_entitlements.find_or_initialize_by(feature_slug: feature_slug.to_s)
    entitlement.assign_attributes(
      active: true,
      source: source,
      granted_at: entitlement.granted_at || Time.current,
      revoked_at: nil
    )
    entitlement.save!
    entitlement
  end

  def revoke_feature!(feature_slug)
    feature_entitlements.find_by(feature_slug: feature_slug.to_s)&.revoke!
  end

  def susu_entitled?
    employee? || admin? || feature_entitlements.active.exists?(feature_slug: "susu")
  end

  def stripe_connect_ready?
    stripe_connect_account_id.present? &&
      stripe_connect_details_submitted? &&
      stripe_connect_payouts_enabled?
  end

'''
if not pattern.search(src):
    raise SystemExit("ERROR: existing can_access_feature? block not found")
src = pattern.sub(replacement, src, count=1)
path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/models/susu_membership.rb")
src = path.read_text()
if "grant_susu_feature_entitlement" not in src:
    idx = src.rfind("\nend")
    if idx < 0:
        raise SystemExit("ERROR: SusuMembership end not found")
    src = src[:idx] + '''
  after_create_commit :grant_susu_feature_entitlement

  private

  def grant_susu_feature_entitlement
    user.grant_feature!(:susu, source: "susu_membership") if user.respond_to?(:grant_feature!)
  end
''' + src[idx:]
    path.write_text(src)
PY

cat > app/services/dymond_bank/stripe_service.rb <<'RUBY'
module DymondBank
  class StripeService
    class ConfigurationError < StandardError; end
    class StripeError < StandardError; end

    class << self
      def create_connect_account!(user)
        configure!
        return retrieve_account(user.stripe_connect_account_id) if user.stripe_connect_account_id.present?

        account = Stripe::Account.create(
          {
            type: "express",
            country: "US",
            email: user.email_address,
            capabilities: { transfers: { requested: true } },
            metadata: { lightek_user_id: user.id.to_s, product: "susu" }
          },
          { idempotency_key: "lightek-connect-user-#{user.id}" }
        )

        user.update!(stripe_connect_account_id: account.id)
        sync_connect_status!(user, account: account)
        account
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      def create_account_link!(user:, refresh_url:, return_url:)
        configure!
        account = create_connect_account!(user)
        Stripe::AccountLink.create(
          account: account.id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: "account_onboarding"
        )
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      def sync_connect_status!(user, account: nil)
        configure!
        account ||= retrieve_account(user.stripe_connect_account_id)
        user.update!(
          stripe_connect_details_submitted: !!account.details_submitted,
          stripe_connect_payouts_enabled: !!account.payouts_enabled,
          stripe_connect_onboarded_at: (account.details_submitted ? (user.stripe_connect_onboarded_at || Time.current) : nil)
        )
        account
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      def create_transfer(amount_cents:, currency:, destination_account:, description:, metadata: {}, idempotency_key: nil)
        configure!
        params = {
          amount: amount_cents.to_i,
          currency: currency.to_s.downcase,
          destination: destination_account,
          description: description,
          metadata: metadata
        }
        options = {}
        options[:idempotency_key] = idempotency_key if idempotency_key.present?
        Stripe::Transfer.create(params, options)
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      def retrieve_account(account_id)
        configure!
        raise ConfigurationError, "Stripe Connect account is missing" if account_id.blank?
        Stripe::Account.retrieve(account_id)
      rescue ::Stripe::StripeError => e
        raise StripeError, e.message
      end

      private

      def configure!
        env_name =
          if DymondBank.respond_to?(:configuration) &&
             DymondBank.configuration.respond_to?(:stripe_secret_key_env)
            DymondBank.configuration.stripe_secret_key_env
          else
            "STRIPE_SECRET_KEY"
          end
        key = ENV[env_name.to_s].presence
        raise ConfigurationError, "#{env_name} is missing" if key.blank?
        Stripe.api_key = key
      end
    end
  end
end
RUBY

cat > app/services/susu/payout_service.rb <<'RUBY'
module Susu
  class PayoutService
    class NotReady < StandardError; end

    def self.request!(round:, requested_by:)
      new(round:, requested_by:).request!
    end

    def initialize(round:, requested_by:)
      @round = round
      @requested_by = requested_by
    end

    def request!
      validate!

      round.with_lock do
        return DymondBank::Payout.find(round.dymond_bank_payout_id) if round.dymond_bank_payout_id.present?

        round.refresh_collected_amount!
        raise NotReady, "Round is not fully funded" unless round.fully_funded?

        recipient = round.recipient
        DymondBank::StripeService.sync_connect_status!(recipient)
        raise NotReady, "Recipient payout account is not ready" unless recipient.stripe_connect_ready?

        payout = DymondBank::Payout.create!(
          recipient: recipient,
          status: "pending",
          currency: "usd",
          amount_cents: Money.from_amount(round.expected_pot).cents,
          fee_cents: 0,
          description: "Susu #{round.susu_group.name} round #{round.number}"
        )

        round.update!(status: "processing", dymond_bank_payout_id: payout.id)

        transfer = DymondBank::StripeService.create_transfer(
          amount_cents: payout.amount_cents,
          currency: payout.currency,
          destination_account: recipient.stripe_connect_account_id,
          description: payout.description,
          metadata: {
            susu_round_id: round.id.to_s,
            susu_group_id: round.susu_group.id.to_s,
            dymond_bank_payout_id: payout.id.to_s
          },
          idempotency_key: "susu-round-payout-#{round.id}"
        )

        payout.update!(status: "paid", processor_ref: transfer.id, paid_at: Time.current)
        Susu::LifecycleService.mark_round_paid_out!(round)
        payout
      rescue StandardError
        payout&.update!(status: "failed")
        round.update!(status: "funded") if round.persisted? && round.status == "processing"
        raise
      end
    end

    private

    attr_reader :round, :requested_by

    def validate!
      raise NotReady, "Round must be funded before payout" unless round.status == "funded" || round.fully_funded?
      raise NotReady, "Only the organizer can request payout" unless round.susu_group.organizer?(requested_by)
      raise NotReady, "Recipient is missing" unless round.recipient
    end
  end
end
RUBY

cat > app/controllers/susu_payout_accounts_controller.rb <<'RUBY'
class SusuPayoutAccountsController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def show
    return if current_user.stripe_connect_account_id.blank?
    DymondBank::StripeService.sync_connect_status!(current_user)
  rescue DymondBank::StripeService::StripeError => e
    flash.now[:alert] = "Could not refresh payout status: #{e.message}"
  end

  def connect
    link = DymondBank::StripeService.create_account_link!(
      user: current_user,
      refresh_url: refresh_dashboard_susu_payout_account_url,
      return_url: dashboard_susu_payout_account_url
    )
    redirect_to link.url, allow_other_host: true, status: :see_other
  rescue DymondBank::StripeService::ConfigurationError, DymondBank::StripeService::StripeError => e
    redirect_to dashboard_susu_payout_account_path, alert: "Payout setup could not start: #{e.message}"
  end

  def refresh
    redirect_to connect_dashboard_susu_payout_account_path, status: :see_other
  end
end
RUBY

cat > app/views/susu_payout_accounts/show.html.erb <<'ERB'
<div class="susu-shell susu-narrow">
  <div class="susu-heading">
    <div class="susu-eyebrow">SUSU PAYOUTS</div>
    <h1>Payout account</h1>
    <p>Connect a Stripe payout account so funded Susu rounds can be transferred to you.</p>
  </div>

  <div class="susu-card">
    <% if current_user.stripe_connect_ready? %>
      <h2>Ready for payouts</h2>
      <p>Your Stripe payout account completed onboarding and is payout-enabled.</p>
    <% else %>
      <h2><%= current_user.stripe_connect_account_id.present? ? "Finish payout setup" : "Connect your payout account" %></h2>
      <p>Stripe-hosted onboarding collects the payout information required for your account.</p>
      <%= button_to "Continue with Stripe",
                    connect_dashboard_susu_payout_account_path,
                    method: :post,
                    class: "susu-button susu-button-primary" %>
    <% end %>
  </div>
</div>
ERB

python3 <<'PY'
from pathlib import Path
path = Path("app/models/susu_round.rb")
src = path.read_text()
if "def dymond_bank_payout" not in src:
    needle = "  def recipient = recipient_membership.user\n"
    if needle not in src:
        raise SystemExit("ERROR: SusuRound recipient method not found")
    src = src.replace(needle, needle + '''
  def dymond_bank_payout
    return if dymond_bank_payout_id.blank?
    DymondBank::Payout.find_by(id: dymond_bank_payout_id)
  end
''', 1)
    path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("app/controllers/susu_groups_controller.rb")
src = path.read_text()

if "request_payout" not in src:
    marker = "\n  def contribution\n"
    method = '''
  def request_payout
    round = @susu_group.current_round_record
    raise Susu::PayoutService::NotReady, "No current Susu round exists" unless round

    payout = Susu::PayoutService.request!(round: round, requested_by: current_user)
    redirect_to @susu_group, notice: "Payout sent. Dymond payout ##{payout.id}."
  rescue Susu::PayoutService::NotReady, DymondBank::StripeService::ConfigurationError, DymondBank::StripeService::StripeError => e
    redirect_to @susu_group, alert: e.message
  end
'''
    if marker not in src:
        raise SystemExit("ERROR: contribution action anchor not found")
    src = src.replace(marker, "\n" + method + marker, 1)

old = "only: %i[show edit update activate contribution contribute request_exit]"
if old in src:
    src = src.replace(old, "only: %i[show edit update activate contribution contribute request_exit request_payout]", 1)

path.write_text(src)
PY

python3 <<'PY'
from pathlib import Path
path = Path("config/routes.rb")
src = path.read_text()

if "request_payout_susu_group" not in src:
    explicit = 'post "/susu_groups/:id/request_payout", to: "susu_groups#request_payout", as: :request_payout_susu_group\n'
    anchor = "resources :susu_match_preferences"
    if anchor not in src:
        raise SystemExit("ERROR: Susu route anchor not found")
    src = src.replace(anchor, explicit + "\n" + anchor, 1)

if "dashboard_susu_payout_account" not in src:
    block = '''post "/dashboard/susu/payout-account/connect", to: "susu_payout_accounts#connect", as: :connect_dashboard_susu_payout_account
get "/dashboard/susu/payout-account/refresh", to: "susu_payout_accounts#refresh", as: :refresh_dashboard_susu_payout_account
get "/dashboard/susu/payout-account", to: "susu_payout_accounts#show", as: :dashboard_susu_payout_account

'''
    mount_anchor = 'mount DymondDash::Engine => "/dashboard"'
    if mount_anchor not in src:
        raise SystemExit("ERROR: DymondDash mount anchor not found")
    src = src.replace(mount_anchor, block + mount_anchor, 1)

path.write_text(src)
PY

cat > lib/tasks/susu_entitlements.rake <<'RUBY'
namespace :susu do
  task backfill_entitlements: :environment do
    ids = SusuGroup.distinct.pluck(:organizer_id) + SusuMembership.distinct.pluck(:user_id)
    users = User.where(id: ids.compact.uniq)
    users.find_each { |user| user.grant_feature!(:susu, source: "susu_backfill") }
    puts "Granted Susu entitlement to #{users.count} existing user(s)."
  end

  task payout_readiness: :environment do
    puts "=== SUSU PAYOUT READINESS ==="
    puts "Stripe mode:         #{ENV["STRIPE_SECRET_KEY"].to_s.start_with?("sk_live_") ? "live" : "test/non-live"}"
    puts "Entitlements table:  #{ActiveRecord::Base.connection.table_exists?("user_feature_entitlements")}"
    puts "Funded rounds:       #{SusuRound.where(status: "funded").count}"
    puts "Processing rounds:   #{SusuRound.where(status: "processing").count}"
  end
end
RUBY

echo "=== SYNTAX ==="
for f in app/models/user_feature_entitlement.rb app/models/user.rb app/models/susu_membership.rb app/models/susu_round.rb app/services/dymond_bank/stripe_service.rb app/services/susu/payout_service.rb app/controllers/susu_payout_accounts_controller.rb app/controllers/susu_groups_controller.rb lib/tasks/susu_entitlements.rake; do
  ruby -c "$f"
done
ruby -c config/routes.rb

echo "=== MIGRATE ==="
bin/rails db:migrate

echo "=== BACKFILL ==="
bin/rails susu:backfill_entitlements

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== ENTITLEMENT CHECK ==="
bin/rails runner '
client = User.where(role: "client").first
if client
  puts "client=#{client.id} susu=#{client.can_access_feature?(:susu)} infrastructure=#{client.can_access_feature?(:gatekeeper_infrastructure)}"
else
  puts "No client user yet; entitlement model loaded."
end
'

echo "=== PAYOUT READINESS ==="
bin/rails susu:payout_readiness

echo "=== ROUTES ==="
bin/rails routes | grep -E 'payout-account|request_payout'

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "DONE"
echo "Backup: $BACKUP"
