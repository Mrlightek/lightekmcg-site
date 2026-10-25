# frozen_string_literal: true
class MarketplaceController < ApplicationController
  allow_unauthenticated_access only: %i[index show]
  skip_authorization_check
  layout "marketplace"

  def index
    @category = params[:category].to_s.presence
    @category = nil unless DymondCatalog::MarketplaceListing.category_labels.key?(@category)
    @listings = DymondCatalog::MarketplaceListing.storefront.includes(offer: :subscription_plan)
    @listings = @listings.where(category: @category) if @category
  end

  def show
    @listing = DymondCatalog::MarketplaceListing.storefront.find(params[:id])
    @offer = @listing.offer
    @intervals = Array(@offer.available_intervals).map(&:to_s)
    @interval = params[:interval].to_s.presence || @offer.default_interval.to_s
    raise ActionController::BadRequest, "Invalid billing interval" unless @intervals.include?(@interval)
    @preview = DymondBank::Checkout.preview(offer: @offer, interval: @interval)
    raise ActionController::BadRequest, "Offer is unavailable" unless @preview[:ok]
  end
end
