# frozen_string_literal: true
module LightekPwa
  class Policy
    class Denied < StandardError; end
    def initialize(user:, site:)
      @user, @site = user, site
    end
    def self.sites_for(user)
      return DymondSite::Site.none unless user
      return DymondSite::Site.all if user.role.to_s == "super_admin"
      owned = DymondSite::Site.where(tenant: user)
      delegated = user.profile ? Membership.where(profile_id: user.profile.id, status: "active", role: %w[admin editor moderator]).select(:site_id) : Membership.none.select(:site_id)
      sites = owned.or(DymondSite::Site.where(id: delegated))
      if defined?(LightekAgency::SiteMembership)
        sites = sites.or(DymondSite::Site.where(id: LightekAgency::SiteMembership.where(user_id: user.id).select(:site_id)))
      end
      sites
    end
    def self.remote_installations_for(user)
      return [] unless user && defined?(GatekeeperInstallation)
      scope = GatekeeperInstallation.where(component: "lightek_app", enabled: true)
      scope = scope.where(account_id: user.id) unless user.role.to_s == "super_admin"
      scope.order(id: :desc).limit(50)
    end
    def self.administration_available_for?(user)
      return false unless user
      return true if user.role.to_s == "super_admin"
      sites_for(user).any? { |site| new(user: user, site: site).manage? } || remote_installations_for(user).any?
    end
    def super_admin? = @user&.role.to_s == "super_admin"
    def owner? = super_admin? || (@user && @site && @site.tenant == @user)
    def membership = @user&.profile && Membership.find_by(site_id: @site&.id, profile_id: @user.profile.id)
    def role
      return "admin" if owner?
      access = membership
      return "member" if access&.status == "suspended"
      return access.role if access && access.role != "member"
      if @user && @site && defined?(LightekAgency::SiteMembership)
        agency = LightekAgency::SiteMembership.find_by(site_id: @site.id, user_id: @user.id)
        return {"manager" => "admin", "designer" => "editor", "marketer" => "moderator"}.fetch(agency.role, "member") if agency
      end
      "member"
    end
    def manage? = %w[admin editor moderator].include?(role)
    def authorize_admin!(section = "overview")
      raise Denied, "This application is outside your administration access" unless manage?
      raise Denied, "Application settings require an administrator" if section == "people" && role != "admin"
      raise Denied, "Application design requires an editor or administrator" if %w[settings navigation].include?(section) && role == "moderator"
      raise Denied, "Studio administration requires an editor or administrator" if section == "studio" && role == "moderator"
      true
    end
    def authorize!(surface = nil)
      return true if super_admin?
      raise Denied, "Your access to this application is suspended" if membership&.status == "suspended"
      app = Application.find_by(site_id: @site&.id) || Application.new(site: @site)
      raise Denied, "This application is under maintenance" unless app.status == "published"
      raise Denied, "This feature is disabled for this application" if surface && !app.surface_enabled?(surface)
      true
    end
    def authorize_capability!(slug)
      surface = case slug.to_s
      when /\Astudio\./ then "studio"
      when /\Amessages\./, /\Amessaging\./, /\Alightek\.messaging\./ then "messages"
      when /\Asusu\./, /\Amoney\./ then "money"
      when /\Acommunity\.(?:profile|top)/, /\Asocial\./ then "space"
      when /\Acommunity\./ then "communities"
      end
      authorize!("create") if slug.to_s.match?(/\Acommunity\.(?:post\.create|create)\z/)
      authorize!(surface)
    end
  end
end
