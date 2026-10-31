module LightekPwa
  class Bootstrap
    def initialize(user: nil, site: nil)
      @user = user
      @site = site
    end

    def call
      if @site && user&.profile
        Membership.find_or_create_by!(site_id: @site.id, profile_id: user.profile.id)
      end
      {
        schema_version: "1.0",
        application: @site ? configuration.app.bootstrap_payload.merge(access_suspended: configuration_policy.membership&.status == "suspended", administration: {role: configuration_policy.role, super_admin: configuration_policy.super_admin?, can_manage: configuration_policy.manage?}) : {id: "lightek", name: "Lightek"},
        identity: identity_payload,
        navigation: navigation_payload,
        surfaces: surface_payload,
        capabilities: capability_payload,
        subscriptions: subscription_payload,
        services: service_payload,
        site: @site && { id: @site.id, name: @site.name, host: @site.host }
      }
    end

    private

    attr_reader :user

      def identity_payload
        return nil unless user

        {
          id: user.id,
          type: user.class.name,
          authenticated: true,
          profile: profile_payload(
            user.profile
          )
        }
      end

      def profile_payload(profile)
        return nil unless profile

        {
          id: profile.id,
          name:
            profile.public_display_name,
          display_name:
            profile.display_name,
          handle:
            profile.handle,
          display_handle:
            profile.display_handle,
          community_gender: profile.community_gender,
          top_people_limit: profile.top_people_limit,
          profile_type:
            profile.profile_type,
          bio:
            profile.bio,
          avatar_url:
            profile.avatar_url,
          cover_image_url:
            profile.cover_image_url,
          sections:
            profile
              .profile_sections
              .ordered
              .where(enabled: true)
              .map do |section|
                {
                  key: section.key,
                  position:
                    section.position,
                  settings:
                    section.settings
                }
              end
        }
      end

    def configuration_policy = @configuration_policy ||= Policy.new(user: user, site: @site)
    def configuration = @configuration ||= Configuration.new(@site)

    def navigation_payload
      return configuration.navigation if @site
      LightekPwa::NavigationItem
        .enabled
        .ordered
        .map(&:bootstrap_payload)
    end

    def surface_payload
      return configuration.surfaces if @site
      LightekPwa::Surface
        .enabled
        .ordered
        .includes(:modules)
        .map(&:bootstrap_payload)
    end

    def capability_payload
      return [] unless defined?(::NevaehCapability)

      ::NevaehCapability
        .where(enabled: true)
        .order(:id)
        .map do |capability|
          {
            slug: capability.slug,
            domain:
              capability.respond_to?(:domain) ?
                capability.domain :
                nil,
            intent:
              capability.respond_to?(:intent_name) ?
                capability.intent_name :
                nil
          }
        end
    end

    def service_payload
      links = [
        { label: "Studio", href: "#/studio" },
        { label: "Communities", href: "#/communities" },
        { label: "Messages", href: "#/messages" },
        { label: "Marketplace", href: "/marketplace" }
      ]
      links << { label: "Storefront", href: "/commerce/shop?site_id=#{@site.id}" } if @site
      if user
        if @site && LightekPwa::Policy.new(user: user, site: @site).manage?
          links << {label: "PWA Administration", href: "/dashboard/pwa?site_id=#{@site.id}"}
        end
        links += [
          { label: "Saved", href: "#/saved" },
          { label: "Money & Susu", href: "#/money" }
        ]
        links << { label: "Mail", href: "/dashboard/mail" } if user.can_access_feature?("mail")
        links << { label: "Live broadcast", href: "/dashboard/live" } if user.can_access_feature?("live")
        if user.role.to_s.in?(%w[admin super_admin]) || (@site && @site.tenant == user)
          links << { label: "Business workspace", href: "/dashboard" }
        end
      end
      links
    end

    def subscription_payload
      items = []

      if user
        items << "user:#{user.id}"
        items << "notifications:user:#{user.id}"
      end

      items
    end
  end
end
