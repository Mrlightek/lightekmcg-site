# frozen_string_literal: true

require 'digest'

module LightekSales
  class CommissionDisbursements
    class Invalid < StandardError; end

    RETRY_WINDOW = 22.hours
    INTENT_REFERENCE = /\Apoi_[a-zA-Z0-9_]{3,150}\z/

    def initialize(actor:, site:, adapter: DymondBank::WorkforcePayouts.new(employer: actor))
      @actor, @site, @adapter = actor, site, adapter
    end

    def link_recipient!(partner:, email:, reference:)
      email = email.to_s.strip.downcase
      reference = reference.to_s.strip
      unless email.length <= 254 && email.match?(URI::MailTo::EMAIL_REGEXP)
        raise Invalid, 'Enter the partner email used for Stripe payout setup.'
      end

      with_owner_lock do
        @site.with_lock do
          authorize!
          partner = Partner.where(site: @site).find(partner.id)
          raise Invalid, 'This partner is using Lightek payout setup.' if partner.payout_setup_started_at?

          sender = @adapter.partner_sender
          @adapter.partner_recipient!(reference: reference, email: email)
          partner.update!(payout_email: email, payout_recipient_ref: reference,
            payout_sender_ref: sender.fetch(:sender_ref), payout_live: sender.fetch(:live))
          audit!('sales_commission_recipient_linked', partner)
        end
      end
    end

    def prepare!(referral:, order_id:)
      payout = reserve!(referral, order_id)
      with_payout(payout) do |current, credit, order|
        ensure_sender!(current)
        if current.provider_ref?
          apply!(current, credit, @adapter.retrieve!(current.provider_ref))
        else
          raise Invalid, 'Find the original intent in Stripe and reconcile it here.' if current.created_at < RETRY_WINDOW.ago

          verify_release_eligibility!(current, credit, order)
          apply!(current, credit, @adapter.prepare_partner_commission!(current))
          audit!('sales_commission_prepared', current)
        end
      end
    end

    def refresh!(payout:, reference: nil)
      with_payout(payout) do |current, credit, _order|
        ensure_sender!(current)
        reference = current.provider_ref || reference.to_s.strip
        raise Invalid, 'Enter the original Stripe payout intent ID.' unless reference.match?(INTENT_REFERENCE)

        result = @adapter.retrieve!(reference)
        raise Invalid, 'Stripe returned a different payout intent.' unless result['id'] == reference

        apply!(current, credit, result)
        audit!('sales_commission_reconciled', current)
      end
    end

    def release!(payout:, review_digest:, proceeds_cleared:)
      raise Invalid, 'Confirm that this order’s proceeds cleared and funded the payout account.' unless proceeds_cleared

      # Persist the first attempted confirmation before any possible money movement.
      reservation = with_payout(payout) do |current, _credit, _order|
        if current.release_attempted_at? && current.state.in?(%w[processing posted sandbox_posted])
          next :already_released
        end
        unless current.provider_ref? && current.state.in?(%w[review confirming]) &&
            current.review_digest? && current.review_digest == review_digest
          raise Invalid, 'Review the current Dymond Bank payout before releasing it.'
        end
        current.update!(state: 'confirming', release_attempted_at: current.release_attempted_at || Time.current,
          released_by: current.released_by || @actor)
      end
      return reservation if reservation == :already_released

      with_payout(payout) do |current, credit, order|
        ensure_sender!(current)
        result = @adapter.retrieve!(current.provider_ref)
        apply!(current, credit, result)
        next unless manual_confirmation?(result)
        next :quote_changed if current.review_digest != review_digest

        verify_release_eligibility!(current, credit, order)
        unless current.review_debit_cents && current.review_debit_cents <= order.merchant_transfer_amount_cents
          raise Invalid, 'Confirmed merchant proceeds must cover the entire payout and its fees.'
        end
        if current.release_attempted_at < RETRY_WINDOW.ago
          raise Invalid, 'The earlier release needs provider reconciliation before any further activity.'
        end

        result = @adapter.release_partner_commission!(current)
        apply!(current, credit, result)
        audit!('sales_commission_release_requested', current)
      end
    end

    private

    def reserve!(referral, order_id)
      with_owner_lock do
        @site.with_lock do
          authorize!
          credit = scoped_referrals.find(referral.id)
          credit.with_lock do
            existing = CommissionPayout.find_by(referral: credit)
            next existing if existing

            order = credit.first_paid_order
            unless order && order.id.to_s == order_id.to_s
              raise Invalid, 'The associated order changed. Review the commission again.'
            end

            order.with_lock do
              verify_order!(credit, order)
              partner = credit.partner
              sender = @adapter.partner_sender
              unless partner.payout_recipient_ref? && partner.payout_sender_ref == sender[:sender_ref] &&
                  partner.payout_live == sender[:live]
                raise Invalid, 'Link the partner’s verified ACH recipient for this Dymond Bank sender.'
              end
              CommissionPayout.create!(referral: credit, order: order, owner: @actor,
                amount_cents: credit.commission_cents, recipient_ref: partner.payout_recipient_ref, **sender)
            end
          end
        end
      end
    end

    def with_payout(payout)
      with_owner_lock do
        @site.with_lock do
          authorize!
          credit = scoped_referrals.find(payout.referral_id)
          credit.with_lock do
            current = CommissionPayout.where(referral: credit, owner: @actor).find(payout.id)
            current.with_lock do
              current.order.with_lock { yield current, credit, current.order }
            end
          end
        end
      end
    end

    def with_owner_lock(&block)
      @actor.with_lock(&block)
    end

    def scoped_referrals
      Referral.where(partner: Partner.where(site: @site))
    end

    def authorize!
      unless @site.tenant_type == 'User' && @site.tenant_id == @actor.id && !@actor.access_suspended_at?
        raise ActiveRecord::RecordNotFound
      end
      if defined?(LightekAgency::Demo) && LightekAgency::Demo.table_exists? &&
          LightekAgency::Demo.where(client_id: @actor.id, cleaned_at: nil).exists?
        raise Invalid, 'Commission payouts are unavailable for demo accounts.'
      end
    end

    def ensure_sender!(payout)
      unless @adapter.partner_sender == {sender_ref: payout.sender_ref, live: payout.live}
        raise Invalid, 'The original Dymond Bank sender is required to manage this payout.'
      end
    end

    def verify_order!(credit, order)
      unless !credit.paid_at? && order.site_id == @site.id && credit.first_paid_order&.id == order.id &&
          credit.payout_status(order) == 'Ready to record'
        raise Invalid, 'The order is no longer eligible for commission payment.'
      end
    end

    def verify_release_eligibility!(payout, credit, order)
      verify_order!(credit, order)
      partner = credit.partner
      unless payout.recipient_ref == partner.payout_recipient_ref && payout.sender_ref == partner.payout_sender_ref &&
          payout.live == partner.payout_live
        raise Invalid, 'The linked payout recipient changed. Reconcile this commission first.'
      end

      @adapter.partner_recipient!(reference: payout.recipient_ref, email: partner.payout_email)
    end

    def manual_confirmation?(result)
      result['status'] == 'requires_action' && result.dig('next_action', 'type') == 'confirm' &&
        result.dig('next_action', 'confirm', 'reason') == 'manually_requested'
    end

    def apply!(payout, credit, result)
      provider_ref = result['id'].to_s
      valid = provider_ref.match?(INTENT_REFERENCE) && (!payout.provider_ref? || payout.provider_ref == provider_ref) &&
        result['livemode'] == payout.live && result['metadata'].is_a?(Hash) &&
        result['metadata'].slice(*payout.provider_metadata.keys) == payout.provider_metadata &&
        result.dig('from', 'financial_account') == payout.sender_ref && result.dig('to', 'recipient') == payout.recipient_ref &&
        result['amount'] == {'value' => payout.amount_cents, 'currency' => 'usd'}
      raise Invalid, 'The provider payout does not match the reserved commission.' unless valid

      debit = result.dig('from', 'debited')
      credited = result.dig('to', 'credited')
      quoted = debit.is_a?(Hash) && debit['currency'] == 'usd' && debit['value'].is_a?(Integer) &&
        debit['value'] >= payout.amount_cents && credited == {'value' => payout.amount_cents, 'currency' => 'usd'} &&
        result['estimated_fees'].is_a?(Array)
      digest = Digest::SHA256.hexdigest(JSON.generate([provider_ref, debit, credited, result['estimated_fees']])) if quoted
      # Verify the outbound payment as well as the payout intent before writing a receipt.
      state = case
      when result['outbound_status'].in?(%w[failed returned]) then result['outbound_status']
      when result['status'] == 'posted' && result['outbound_status'] == 'posted' then payout.live ? 'posted' : 'sandbox_posted'
      when result['status'].in?(%w[canceled failed returned]) then result['status']
      when result['status'].in?(%w[pending processing posted]) then 'processing'
      when manual_confirmation?(result) && quoted then 'review'
      else 'provider_action'
      end

      payout.update!(provider_ref: provider_ref, state: state,
        review_debit_cents: (debit['value'] if quoted), review_digest: digest)
      if state == 'posted' && !credit.paid_at?
        credit.update!(order: payout.order, payout_reference: provider_ref,
          recorded_by: payout.released_by || @actor, paid_at: Time.current)
      end
    end

    def audit!(action, record)
      LightekPeople::AuditEvent.record!(employer: @actor, actor: @actor, action: action, record: record)
    end
  end
end
