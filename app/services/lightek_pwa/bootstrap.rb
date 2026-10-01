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
        type: user.class.name
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
