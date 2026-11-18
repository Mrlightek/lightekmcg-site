module LightekPwa
  # Fresh native member databases need the same functional registries as the
  # central app. Run explicitly during installation/update, never on page reads.
  class MemberRuntime
    SEEDS = %w[lightek_messaging_capabilities studio_pwa_capabilities
      studio_scene_object_capabilities lightek_community_capabilities
      lightek_studio_workspace_capabilities].freeze

    def self.prepare!
      return false unless ENV['LIGHTEK_PWA_MEMBER_BACKEND'] == 'true'
      Surface.transaction do
        connection = Surface.connection
        if connection.adapter_name == 'PostgreSQL'
          connection.select_value('SELECT pg_advisory_xact_lock(731842691)')
        end
        # An existing registry can contain deliberately disabled/custom entries.
        # Initialize only completely empty registries; never reset them on update.
        load Rails.root.join('db/seeds/lightek_pwa_storefront.rb') unless Surface.exists?
        unless NevaehCapability.exists?
          SEEDS.each { |name| load Rails.root.join("db/seeds/#{name}.rb") }
        end
      end
      true
    end
  end
end
