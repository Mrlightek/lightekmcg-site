# frozen_string_literal: true

module LightekTeam
  class Installation
    def self.site
      host = ENV['LIGHTEK_DEPLOYED_SITE_HOST'].presence || ENV['APP_HOST'].presence
      record = DymondSite::Site.find_by(host: host) if host
      record if record && LightekReservations::Federation::Client.config(record).present?
    end

    def initialize(actor)
      raise LightekPeople::Access::Denied unless actor

      @site = self.class.site || raise(LightekPeople::Access::Denied)
      @actor = actor
      @organization = @site.tenant
      raise LightekPeople::Access::Denied unless @organization.is_a?(User) && LightekPeople::LifecycleAccess.active?(@organization)

      @access = LightekPeople::Access.new(actor: actor, employer: @organization)
      @access.require_active!
    end

    def owner? = @access.owner?

    def members
      LightekTeam::Workspace.new(actor: @actor, employer: @organization).roster.where.not(id: @organization.id)
    end

    def request(path, attributes = {})
      @access.require_active!
      LightekReservations::Federation::Client.new(@site).request(path, method: :post,
        body: attributes.merge(subject: owner? ? 'owner' : "user-#{@actor.id}", actor_name: @actor.full_name))
    end
  end
end
