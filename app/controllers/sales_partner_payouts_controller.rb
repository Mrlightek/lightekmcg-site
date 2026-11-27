# frozen_string_literal: true

class SalesPartnerPayoutsController < ApplicationController
  layout 'auth'
  protect_from_forgery with: :exception
  before_action :set_setup

  rescue_from LightekSales::PartnerPayoutOnboarding::Invalid, DymondBank::WorkforcePayouts::Unavailable,
    DymondBank::WorkforcePayouts::ProviderError do |error|
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def show
    @ready = @setup.ready?
  end

  def create
    local_url = sales_partner_payout_setup_url(id: @partner.id, protocol: 'https')
    url = @setup.start!(return_url: local_url, refresh_url: local_url, entity_type: params[:entity_type].to_s)
    redirect_to(url || local_url, allow_other_host: url.present?, status: :see_other)
  end

  private

  def set_setup
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'no-referrer')
    response.set_header('X-Robots-Tag', 'noindex')
    raise ActiveRecord::RecordNotFound if Current.session&.connect_delegation.present?

    @partner = LightekSales::Partner.find(params[:id])
    @token = params[:setup_token].to_s
    @setup = LightekSales::PartnerPayoutOnboarding.new(actor: current_user, partner: @partner, token: @token)
    @setup.authorize!
  end
end
