# frozen_string_literal: true

# Host-application features exposed through DymondDash's native FeatureRegistry.
#
# DymondDash builds sidebar navigation from FeatureRegistry.nav_items_for, so
# Gatekeeper and Susu belong here rather than in a second navigation registry.
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :gatekeeper_infrastructure
    f.label       = "Infrastructure"
    f.icon        = "server"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Infrastructure",
        icon: "server",
        path: "main_app.dashboard_infrastructure_path"
      }
    ]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :susu
    f.label       = "Susu"
    f.icon        = "users-group"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :services
    f.min_plan    = :starter
    f.nav_items   = [
      {
        label: "Susu",
        icon: "users-group",
        path: "main_app.dashboard_susu_path"
      }
    ]
  end
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :network_control
    f.label = "Network & Domains"
    f.icon = "world-cog"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Network & Domains", icon: "world-cog", path: "main_app.dashboard_network_path" }]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :vault
    f.label       = "Lightek Vault"
    f.icon        = "lock"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [{ label: "Lightek Vault", icon: "lock", path: "main_app.dashboard_vault_path" }]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug = :compute_provider_management
    f.label = "Compute Providers"
    f.icon = "server-cog"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Compute Providers", icon: "server-cog", path: "main_app.dashboard_compute_providers_path" }]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug = :infrastructure_catalog
    f.label = "Infrastructure Catalog"
    f.icon = "server"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Infrastructure Catalog", icon: "server", path: "main_app.dashboard_infrastructure_catalog_path" }]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug = :subscription_plan_management
    f.label = "Subscription Plans"
    f.icon = "credit-card"
    f.gem_source = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan = :starter
    f.nav_items = [{ label: "Subscription Plans", icon: "credit-card", path: "main_app.dashboard_subscription_plans_path" }]
  end

  DymondDash::FeatureRegistry.register do |f|
    f.slug        = :provisioning_requests
    f.label       = "Provisioning Requests"
    f.icon        = "server-bolt"
    f.gem_source  = "lightekmcg-site"
    f.nav_section = :operations
    f.min_plan    = :starter
    f.nav_items   = [{
      label: "Provisioning Requests",
      icon: "server-bolt",
      path: "main_app.dashboard_provisioning_requests_path"
    }]
  end

rescue StandardError => e
  Rails.logger.warn "[Lightek/DymondDash] Host feature registration skipped: #{e.class}: #{e.message}"
end
