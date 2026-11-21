# frozen_string_literal: true

class BroadcastViewingLinksController < ApplicationController
  allow_unauthenticated_access only: :redeem
  skip_forgery_protection only: :redeem
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rate_limit to: 20, within: 1.minute, only: :redeem

  def create
    site = LightekPwa::SiteContext.resolve(request.host)
    @viewing_code = Studio::Advertising::ViewingLink.issue!(site: site, user: current_user).scan(/.{4}/).join("-")
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def redeem
    site = LightekPwa::SiteContext.resolve(request.host)
    token = Studio::Advertising::ViewingLink.redeem!(site: site, code: params[:viewing_code])
    render json: { token: token }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "The linking code is invalid, expired, or already used." }, status: :unprocessable_entity
  end
end
