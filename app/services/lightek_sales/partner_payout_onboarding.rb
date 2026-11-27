# frozen_string_literal: true

module LightekSales
  class PartnerPayoutOnboarding
    class Invalid < StandardError; end
    RETRY_WINDOW = 22.hours

    def initialize(actor:, partner:, token: nil, adapter: nil)
      @actor, @partner, @token = actor, partner, token
      @site = partner.site
      @owner = @site.tenant if @site.tenant_type == 'User'
      @adapter = adapter || DymondBank::WorkforcePayouts.new(employer: @owner)
    end

    def authorize!
      allowed = @actor && !@actor.access_suspended_at? && @owner && !@owner.access_suspended_at? &&
        @site.tenant_type == 'User' && @site.tenant_id == @owner.id && @partner.payout_invited_by_id == @owner.id &&
        !@partner.revoked_at? && @actor.email_address.casecmp?(@partner.payout_email.to_s)
      raise ActiveRecord::RecordNotFound unless allowed

      claimed = @partner.payout_user_id
      unless claimed ? claimed == @actor.id : Partner.find_by_token_for(:payout_setup, @token)&.id == @partner.id
        raise ActiveRecord::RecordNotFound
      end
      LightekAgency::PackagePolicy.authorize!(@owner, 'commerce')
      if defined?(LightekAgency::Demo) && LightekAgency::Demo.table_exists? &&
          LightekAgency::Demo.where(client_id: @owner.id, cleaned_at: nil).exists?
        raise ActiveRecord::RecordNotFound
      end
      true
    end

    def ready?
      authorize!
      return false unless @partner.payout_recipient_ref?

      verify_sender!
      @adapter.partner_recipient!(reference: @partner.payout_recipient_ref, email: @partner.payout_email)
      true
    rescue DymondBank::WorkforcePayouts::Unavailable
      false
    end

    def start!(return_url:, refresh_url:, entity_type: nil)
      # Commit the claim and sender before calling Stripe. An interrupted
      # recipient creation can replay only the original idempotent request.
      with_setup_lock do
        unless @partner.payout_setup_started_at?
          raise Invalid, 'Choose individual or business.' unless entity_type.in?(%w[individual company])

          sender = @adapter.partner_sender
          @partner.update!(payout_user: @actor, payout_entity_type: entity_type, payout_setup_started_at: Time.current,
            payout_sender_ref: sender.fetch(:sender_ref), payout_live: sender.fetch(:live))
        end
      end

      with_setup_lock do
        verify_sender!
        unless @partner.payout_recipient_ref?
          if @partner.payout_setup_started_at < RETRY_WINDOW.ago
            raise Invalid, 'Recipient creation needs to be reconciled before it can continue.'
          end
          @partner.update!(payout_recipient_ref: @adapter.create_partner_recipient!(@partner))
        end
      end

      with_setup_lock do
        verify_sender!
        next if ready?

        @adapter.partner_onboarding_link!(reference: @partner.payout_recipient_ref,
          return_url: return_url, refresh_url: refresh_url)
      end
    end

    private

    def with_setup_lock
      authorize!
      @owner.with_lock do
        @site.with_lock do
          @partner.with_lock do
            @actor.reload
            authorize!
            yield
          end
        end
      end
    end

    def verify_sender!
      unless @adapter.partner_sender == {sender_ref: @partner.payout_sender_ref, live: @partner.payout_live}
        raise Invalid, 'The original payout sender is required to continue setup.'
      end
    end
  end
end
