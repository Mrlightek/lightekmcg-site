#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/studio_monetization_v1_${STAMP}"

mkdir -p "$BACKUP/app/models"
mkdir -p app/services/studio/billing

cp app/models/studio_operation.rb \
  "$BACKUP/app/models/studio_operation.rb"

echo "==> Installing Studio billing pricing"

cat > app/services/studio/billing/pricing.rb <<'RUBY'
# frozen_string_literal: true

module Studio
  module Billing
    class Pricing
      class ConfigurationError < StandardError; end

      DEVELOPMENT_DEFAULTS = {
        "build_scene" => 500
      }.freeze

      ENV_KEYS = {
        "build_scene" => "STUDIO_BUILD_SCENE_PRICE_CENTS"
      }.freeze

      def self.principal_cents_for(operation_type)
        operation_type = operation_type.to_s

        env_key = ENV_KEYS.fetch(operation_type) do
          raise ConfigurationError,
                "No Studio pricing configuration exists for #{operation_type.inspect}"
        end

        raw =
          if ENV.key?(env_key)
            ENV.fetch(env_key)
          elsif Rails.env.production?
            raise ConfigurationError,
                  "#{env_key} must be configured in production"
          else
            DEVELOPMENT_DEFAULTS.fetch(operation_type)
          end

        cents = Integer(raw)

        unless cents.positive?
          raise ConfigurationError,
                "#{env_key} must be greater than zero"
        end

        cents
      rescue ArgumentError, TypeError
        raise ConfigurationError,
              "#{env_key} must contain an integer number of cents"
      end
    end
  end
end
RUBY

echo "==> Installing Studio quote service"

cat > app/services/studio/billing/quote.rb <<'RUBY'
# frozen_string_literal: true

module Studio
  module Billing
    class Quote
      DEFAULT_RAIL = :stripe_ach
      CONTEXTS = {
        "build_scene" => :studio_render
      }.freeze

      def self.call(operation:, rail: DEFAULT_RAIL)
        new(operation:, rail:).call
      end

      def initialize(operation:, rail:)
        @operation = operation
        @rail = rail.to_sym
      end

      def call
        principal_cents =
          Studio::Billing::Pricing.principal_cents_for(
            operation.operation_type
          )

        context = CONTEXTS.fetch(operation.operation_type) do
          raise ArgumentError,
                "No billing context configured for #{operation.operation_type.inspect}"
        end

        quote = DymondBank::PaymentQuote.call(
          principal_cents: principal_cents,
          rail: rail,
          context: context
        )

        payload = stringify_quote(quote).merge(
          "quoted_at" => Time.current.iso8601,
          "description" => description
        )

        operation.update!(
          cost_quote: payload,
          status: "awaiting_payment",
          error_message: nil
        )

        quote
      end

      private

      attr_reader :operation, :rail

      def stringify_quote(quote)
        quote.to_h.each_with_object({}) do |(key, value), result|
          result[key.to_s] =
            value.is_a?(Symbol) ? value.to_s : value
        end
      end

      def description
        case operation.operation_type
        when "build_scene"
          scene_name =
            operation.studio_scene&.name.presence ||
            "Studio Scene"

          "Studio render — #{scene_name}"
        else
          "Studio operation — #{operation.operation_type.humanize}"
        end
      end
    end
  end
end
RUBY

echo "==> Installing Studio checkout service"

cat > app/services/studio/billing/checkout.rb <<'RUBY'
# frozen_string_literal: true

module Studio
  module Billing
    class Checkout
      class QuoteMissing < StandardError; end
      class AlreadyPaid < StandardError; end

      def self.call(operation:, payer:, success_url:, cancel_url:)
        new(
          operation:,
          payer:,
          success_url:,
          cancel_url:
        ).call
      end

      def initialize(operation:, payer:, success_url:, cancel_url:)
        @operation = operation
        @payer = payer
        @success_url = success_url
        @cancel_url = cancel_url
      end

      def call
        raise AlreadyPaid, "Studio operation is already paid" if operation.paid?

        quote = operation.cost_quote.to_h

        if quote.blank? || quote["principal_cents"].to_i <= 0
          raise QuoteMissing,
                "Studio operation must have a valid quote before checkout"
        end

        rail = quote.fetch("rail", "stripe_ach").to_sym
        context = quote.fetch("context", "studio_render").to_sym

        unless rail == :stripe_ach
          raise ArgumentError,
                "Studio checkout currently supports stripe_ach only"
        end

        DymondBank::StripeCheckoutService.create_for_payable!(
          payable: operation,
          payer: payer,
          principal_cents: quote.fetch("principal_cents").to_i,
          context: context,
          description: quote.fetch(
            "description",
            "Studio #{operation.operation_type.humanize}"
          ),
          success_url: success_url,
          cancel_url: cancel_url
        )
      end

      private

      attr_reader :operation, :payer, :success_url, :cancel_url
    end
  end
end
RUBY

echo "==> Extending StudioOperation payment lifecycle"

python3 <<'PY'
from pathlib import Path

path = Path("app/models/studio_operation.rb")
src = path.read_text()

src = src.replace(
    'STATUSES = %w[awaiting_planning awaiting_approval pending running completed failed cancelled].freeze',
    'STATUSES = %w[awaiting_planning awaiting_approval awaiting_payment pending running completed failed cancelled].freeze'
)

if "def payment_required?" not in src:
    marker = '  def terminal? = status.in?(%w[completed failed cancelled])\n'

    addition = '''  def payment_required? = status == "awaiting_payment"

  def paid?
    return false unless defined?(DymondBank::Transaction)

    DymondBank::Transaction
      .succeeded
      .where(payable: self)
      .exists?
  end

  def payment_succeeded!(transaction)
    with_lock do
      current_metadata = metadata.to_h.deep_dup

      payment_metadata =
        current_metadata.fetch("payment", {}).merge(
          "transaction_id" => transaction.id,
          "status" => "succeeded",
          "paid_at" => Time.current.iso8601
        )

      update!(
        status: "pending",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: nil
      )
    end

    ExecuteStudioOperationJob.perform_later(id)

    self
  end

  def payment_failed!(transaction, message: nil)
    with_lock do
      current_metadata = metadata.to_h.deep_dup

      payment_metadata =
        current_metadata.fetch("payment", {}).merge(
          "transaction_id" => transaction.id,
          "status" => "failed",
          "failed_at" => Time.current.iso8601
        )

      update!(
        status: "awaiting_payment",
        metadata: current_metadata.merge("payment" => payment_metadata),
        error_message: message.to_s.presence
      )
    end

    self
  end

'''

    if marker not in src:
        raise SystemExit("ERROR: StudioOperation terminal? anchor not found")

    src = src.replace(marker, addition + marker, 1)

path.write_text(src)

print("StudioOperation payment lifecycle installed.")
PY

echo
echo "===== RUBY SYNTAX ====="

ruby -c app/models/studio_operation.rb
ruby -c app/services/studio/billing/pricing.rb
ruby -c app/services/studio/billing/quote.rb
ruby -c app/services/studio/billing/checkout.rb

echo
echo "===== DIFF CHECK ====="
git diff --check

echo
echo "===== ZEITWERK ====="
bin/rails zeitwerk:check

echo
echo "===== STATUS ====="
git status --short

echo
echo "Studio monetization core installed."
echo "Backup: $BACKUP"
