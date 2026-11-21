# frozen_string_literal: true

class Api::BroadcastAdExchangeController < Api::ReservationFederationController
  before_action :limit_upload, only: :save_offer
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: "This reference already belongs to another ad network." }, status: :conflict
  end
  rescue_from Studio::Advertising::Exchange::Unavailable do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def catalog
    campaigns = Studio::Advertising::Exchange.public_offers.includes(:network, asset: { proxy_attachment: :blob })
      .order(id: :desc).limit(100).select do |campaign|
        campaign.creative_available? && campaign.asset.proxy.blob.byte_size.between?(1, Studio::Advertising::Exchange::MAX_CREATIVE)
      end
    render json: { campaigns: campaigns.map { |campaign| Studio::Advertising::Exchange.serialize(campaign) } }
  end

  def sales
    _, site = Studio::Advertising::Exchange.business!(@peer, params.require(:merchant_key))
    campaigns = Studio::Advertising::Campaign.joins(:network).where(studio_ad_networks: { peer_id: @peer.id, site_id: site.id })
    slots = Studio::Advertising::Placement.where(campaign: campaigns)
    payments = Studio::Advertising::Payment.where(placement: slots).includes(placement: [:campaign, :airing]).order(id: :desc).limit(50)
    render json: {
      site_id: site.id, payments: payments.map { |payment| {
        name: payment.placement.campaign.name, state: payment.state,
        key: payment.public_key, payable: payment.state == "unfunded" && payment.can_book_payment?
      } }
    }
  end

  def offer
    campaign = Studio::Advertising::Exchange.public_offers.find_by!(exchange_key: params[:key])
    render json: Studio::Advertising::Exchange.serialize(campaign).merge(Studio::Advertising::Exchange.creative_payload(campaign))
  end

  def save_offer
    values = params.permit(:network_key, :network_name, :merchant_key, :open, :media, :sha256, *Studio::Advertising::Exchange::TERMS).to_h
    render json: Studio::Advertising::Exchange.receive_offer!(@peer, params[:key], values)
  end

  def placement
    values = params.permit(:campaign_key, :merchant_key, :starts_at, :ends_at, :producer_key, :published, :delivered_at, :retired).to_h
    render json: Studio::Advertising::Exchange.receive_placement!(@peer, params[:key], values)
  end

  private

  def limit_upload
    head :payload_too_large if request.content_length.nil? || request.content_length > 9.megabytes
  end
end
