# frozen_string_literal: true

class SalesPartnerPayoutMailer < ApplicationMailer
  def setup(partner_id, email, owner_id)
    @partner = LightekSales::Partner.find_by(id: partner_id, payout_email: email, payout_invited_by_id: owner_id,
      payout_user_id: nil, revoked_at: nil)
    return unless @partner && @partner.site.tenant_type == 'User' && @partner.site.tenant_id == owner_id

    @setup_url = sales_partner_payout_setup_url(id: @partner.id, setup_token: @partner.generate_token_for(:payout_setup))
    mail(to: email, subject: 'Set up your Lightek commission payouts')
  end
end
