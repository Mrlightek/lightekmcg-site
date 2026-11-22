# frozen_string_literal: true

class MediaWebsiteController < ApplicationController
  PAGES = {
    "creators" => "Creators",
    "watch" => "Watch",
    "stations" => "Stations",
    "sponsors" => "Sponsors",
    "crew" => "Crew",
    "agencies" => "Agencies",
    "press" => "Press"
  }.freeze

  allow_unauthenticated_access only: %i[index show]
  layout "media_website"

  def index
    render :index
  end

  def show
    @page = params[:page]
    return head :not_found unless PAGES.key?(@page)

    @title = PAGES.fetch(@page)
    if @page == "agencies"
      site = DymondSite::Site.find_by(host: request.host.downcase)
      @agency_demo_available = LightekAgency::Trial.public_site?(site)
      @agency_price_cents = if site
        LightekAgency::Trial.annual_price_cents(site)
      else
        LightekAgency::Trial::DEFAULT_ANNUAL_PRICE_CENTS
      end
    end
    if @page == "press"
      site = DymondSite::Site.find_by(host: request.host.downcase)
      @press_releases = NevaehOs::PublicRelations.releases(site).limit(10) if site
    end
    render @page
  end
end
