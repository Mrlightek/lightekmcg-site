# frozen_string_literal: true
class Dashboard::ClientHomeController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"

  def index
    response.headers["Cache-Control"] = "no-store, private"
    @agency_profile = current_user.agency&.agency_profile
    @sites = LightekAgency::Access.sites_for(current_user).order(:name, :id)
    @installations = LightekCommerce::Installations.scope_for(current_user)
      .order(created_at: :desc).limit(20).map { |order| [order, LightekCommerce::Installations.summary(order)] }
    @voice_available = LightekTeam::Installation.site&.tenant == current_user &&
      !current_user.password_setup_required? && Current.session&.connect_delegation.blank?
    @mfa_enabled = LightekIdentity::Mfa.enabled?(current_user)
    @agency_trial = LightekAgency::Trial.find_by(prospect: current_user) if defined?(LightekAgency::Trial) && LightekAgency::Trial.table_exists?
    @demos = LightekAgency::Demo.where(client: current_user).order(created_at: :desc).limit(10)
  end
end
