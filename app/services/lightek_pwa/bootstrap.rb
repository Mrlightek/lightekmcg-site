module LightekPwa
  class Bootstrap
    def initialize(user: nil)
      @user = user
    end

    def call
      {
        schema_version: "1.0",
        application: {
          id: "lightek",
          name: "Lightek"
        },
        identity: identity_payload,
        navigation: navigation_payload,
        surfaces: surface_payload,
        capabilities: capability_payload,
        subscriptions: subscription_payload
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

    def navigation_payload
      LightekPwa::NavigationItem
        .enabled
        .ordered
        .map(&:bootstrap_payload)
    end

    def surface_payload
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
