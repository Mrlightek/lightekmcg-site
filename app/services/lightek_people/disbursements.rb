require 'digest'
module LightekPeople
  class Disbursements
    def initialize(access:, adapter: nil)
      @access = access
      @adapter = adapter || DymondBank::WorkforcePayouts.new(employer: access.employer)
    end
    def self.quote_digest(quote) = Digest::SHA256.hexdigest(JSON.generate(quote))
    def perform!(statement:, action:, review_digest: nil)
      @access.require!(:release)
      run = statement.pay_run
      raise Access::Denied, 'Pay statement belongs to another employer' unless run.employer_id == @access.employer.id
      reserve_attempt!(statement) if action == 'prepare'
      error = nil
      # The employer lock also serializes membership changes and key rotation.
      @access.employer.with_lock do
        @access.require!(:release)
        run.with_lock do
          raise Payroll::Invalid, 'Approve this run before preparing disbursements' unless run.approved?
          raise Payroll::Invalid, 'This pay date is in the future' if run.pay_date > Date.current && action != 'refresh'
          statement.reload
          raise Payroll::Invalid, 'Zero net pay does not require a bank payout' unless statement.net_cents.positive?
          begin
            case action
            when 'prepare'
              if statement.provider_ref.present?
                result = @adapter.retrieve!(statement.provider_ref)
              else
                if statement.attempted_at && statement.attempted_at < 23.hours.ago
                  raise Payroll::Invalid, 'Unresolved provider attempt: reconcile with Stripe before another attempt; do not create a replacement payment'
                end
                statement.update!(status: 'preparing', error_code: nil)
                result = @adapter.prepare!(statement)
              end
            when 'confirm'
              raise Payroll::Invalid, 'Review the current provider quote before release' unless review_digest == self.class.quote_digest(statement.quote)
              raise Payroll::Invalid, 'Prepare and review this payout first' unless statement.provider_ref.present?
              result = @adapter.retrieve!(statement.provider_ref)
              verify!(statement, result)
              if result['status'] == 'requires_action'
                reason = result.dig('next_action','confirm','reason')
                raise Payroll::Invalid, 'Stripe requires additional review; resolve it in Stripe and refresh here' unless result.dig('next_action','type') == 'confirm' && reason == 'manually_requested'
                raise Payroll::Invalid, 'Provider fee quote unavailable; refresh before release' if result['estimated_fees'].nil?
                fresh_quote = quote_for(result)
                unless statement.quote == fresh_quote
                  apply!(statement, result)
                  raise Payroll::Invalid, 'Provider fees changed. Review the refreshed quote before releasing net pay'
                end
                result = @adapter.confirm!(statement)
              end
            when 'refresh'
              raise Payroll::Invalid, 'This statement has no provider payout yet' unless statement.provider_ref.present?
              result = @adapter.retrieve!(statement.provider_ref)
            else
              raise Payroll::Invalid, 'Unknown disbursement action'
            end
            verify!(statement, result)
            apply!(statement, result)
            AuditEvent.record!(employer: @access.employer, actor: @access.actor, action: "payout_#{action}", record: statement)
          rescue DymondBank::WorkforcePayouts::ProviderError, DymondBank::WorkforcePayouts::Unavailable, Payroll::Invalid => exception
            statement.update!(error_code: exception.class.name.demodulize)
            error = exception
          end
        end
      end
      raise error if error
      statement
    end
    private
    def reserve_attempt!(statement)
      raise Payroll::Invalid, 'Payout creation must start outside a database transaction' if ApplicationRecord.connection.open_transactions.positive?
      @access.employer.with_lock do
        @access.require!(:release)
        statement.pay_run.with_lock do
          raise Payroll::Invalid, 'Approve this run first' unless statement.pay_run.approved?
          raise Payroll::Invalid, 'This pay date is in the future' if statement.pay_run.pay_date > Date.current
          statement.reload
          raise Payroll::Invalid, 'Net pay must be positive' unless statement.net_cents.positive?
          statement.update!(attempted_at: Time.current) unless statement.attempted_at
        end
      end
    end
    def quote_for(result)
      {'fees'=>result['estimated_fees'], 'debited'=>result.dig('from','debited'), 'credited'=>result.dig('to','credited'),
        'next_action'=>result.dig('next_action','type')}.compact
    end
    def verify!(statement, result)
      run = statement.pay_run
      destination = statement.employment.payout_destination
      valid = result['id'].to_s.match?(/\Apoi_[a-zA-Z0-9_]+\z/) &&
        (statement.provider_ref.blank? || result['id'] == statement.provider_ref) &&
        result.dig('from','financial_account') == run.financial_account_ref &&
        result.dig('to','recipient') == destination&.recipient_ref &&
        result.dig('amount','value') == statement.net_cents && result.dig('amount','currency') == run.currency.downcase
      raise Payroll::Invalid, 'Provider payout differs from the approved pay statement' unless valid
    end
    def apply!(statement, result)
      status = result['status'].to_s
      local = case status
      when 'requires_action'
        result.dig('next_action','confirm','reason') == 'manually_requested' ? 'review' : 'requires_action'
      when 'pending', 'processing' then 'pending'
      when 'posted' then 'posted'
      when 'failed', 'canceled' then 'failed'
      when 'returned' then 'returned'
      else 'requires_action'
      end
      local = result['outbound_status'] if %w[failed returned].include?(result['outbound_status'])
      quote = quote_for(result)
      statement.update!(provider_ref: result.fetch('id'), provider_status: status.slice(0,80), status: local, quote: quote, error_code: nil)
    end
  end
end
