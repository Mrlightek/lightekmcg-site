# frozen_string_literal: true
require "rails/railtie"
require "dymond_dash/feature_registry"
module Lightek
  module DashboardBootSync
    private
    def sync_to_db(definition)
      return unless Rails.application.config.x.lightek_dashboard_models_ready == true
      super
    end
  end
  DymondDash::FeatureRegistry.singleton_class.prepend(DashboardBootSync)

  class DashboardBootSyncRailtie < Rails::Railtie
    initializer "lightek.defer_dashboard_feature_sync", before: :load_config_initializers do |app|
      app.config.after_initialize do
        app.config.x.lightek_dashboard_models_ready = true
        registry = DymondDash::FeatureRegistry
        if registry.send(:db_available?)
          registry.all.each { |definition| registry.send(:sync_to_db, definition) }
        end
      end
    end
  end
end
