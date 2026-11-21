# frozen_string_literal: true

require "builder"

class BroadcastAdDecisionsController < ApplicationController
  allow_unauthenticated_access

  def show
    response.set_header("Cache-Control", "private, no-store")
    site = LightekPwa::SiteContext.resolve(request.host)
    profile = Studio::Advertising::StreamProfile.find_by!(site: site, decision_key: params[:decision_key])
    return head :not_found unless profile.channel.status == "published"

    sources = Studio::Advertising::DemandSource.where(site: site, enabled: true, platform: ["both", profile.platform]).order(:position, :id).limit(20)
    render xml: vast(sources), content_type: "application/xml"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def impression
    response.set_header("Cache-Control", "no-store")
    head :no_content
  end

  private

  def vast(sources)
    xml = Builder::XmlMarkup.new
    xml.instruct!
    xml.VAST(version: "3.0") do
      sources.each do |source|
        tag = usable_tag(source)
        next unless tag

        xml.Ad(id: "demand-#{source.id}") do
          xml.Wrapper(followAdditionalWrappers: true, allowMultipleAds: true, fallbackOnNoAd: true) do
            xml.AdSystem("LightekMCG")
            xml.VASTAdTagURI(tag)
            xml.Impression(broadcast_wrapper_impression_url)
            xml.Creatives
          end
        end
      end
    end
  end

  def usable_tag(source)
    tag = source.tag
    tag if Studio::Advertising::DemandSource.https_url?(tag)
  rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied, LightekVault::Crypto::DecryptionError, KeyError
    nil
  end
end
