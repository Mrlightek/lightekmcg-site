module Api
  class PwaMemberBackendsController < ApplicationController
    allow_unauthenticated_access only: :health
    skip_authorization_check
    protect_from_forgery with: :exception
    before_action :context, except: :health
    rescue_from LightekPwa::MemberBackends::Unavailable do |e|
      render json: {error: e.message}, status: :unprocessable_entity
    end
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    def health
      response.set_header('Cache-Control', 'no-store')
      site = LightekPwa::SiteContext.resolve(request.host)
      member = site.manifest.to_h['pwa_member'] or raise ActiveRecord::RecordNotFound
      render json: {member_key: member.fetch('key')}
    end
    def show
      response.set_header('Cache-Control', 'private, no-store')
      backend = LightekPwa::MemberBackend.find_by(site: @site, user: current_user)
      render json: {backend: backend&.summary}
    end
    def create
      backend = LightekPwa::MemberBackends.reserve!(site: @site, user: current_user)
      render json: {backend: backend&.summary}
    end
    def open
      backend = LightekPwa::MemberBackend.find_by!(site: @site, user: current_user)
      render json: {url: LightekPwa::MemberBackends.issue_ticket!(backend: backend, user: current_user)}
    end
    private
    def context
      @site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: current_user, site: @site).authorize!
    end
  end
end
