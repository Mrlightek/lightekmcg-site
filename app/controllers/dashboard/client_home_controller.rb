# frozen_string_literal: true
class Dashboard::ClientHomeController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    response.headers["Cache-Control"] = "no-store, private"
    @agency_profile = current_user.agency&.agency_profile
    @sites = LightekAgency::Access.sites_for(current_user).order(:name, :id)
    @installations = LightekCommerce::Installations.scope_for(current_user)
      .order(created_at: :desc).limit(20).map { |order| [order, LightekCommerce::Installations.summary(order)] }
    @mfa_enabled = LightekIdentity::Mfa.enabled?(current_user)
    @demos = LightekAgency::Demo.where(client: current_user).order(created_at: :desc).limit(10)
  end
end
