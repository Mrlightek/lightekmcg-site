require 'uri'
module LightekAgency
  class PackageFeatures
    PUBLIC_BASELINE = %w[sessions passwords account_setups identity_security identity_challenges identity_onboarding identity_sso installations dashboard/installations dashboard/client_home dashboard/account_settings dashboard/settings_home dashboard/appearance_colors supports commerce_stripe_webhooks api/reservation_federation api/commerce_network api/connect_instance gatekeeper/callbacks gatekeeper/fleet_health].freeze
    PREFIXES = {
      'studio' => %w[dymond_studio dashboard/media_studio dashboard/studio_ api/studio],
      'live' => %w[dashboard/live_broadcasts], 'rooms' => %w[dashboard/rooms dashboard/session_media session_rooms],
      'reservations' => %w[dymond_booking dashboard/reservations reservations network_reservations],
      'shipping' => %w[dashboard/shipping commerce_shipping_quotes api/shipping_broker],
      'payments' => %w[dymond_bank dashboard/bank], 'knowledge' => %w[dymond_kb],
      'commerce' => %w[dymond_catalog dashboard/commerce commerce stores dashboard/customers marketplace dashboard/marketplace catalogs],
      'marketing' => %w[dashboard/marketing_ dashboard/social_connections dashboard/meta_connections dashboard/tiktok_connections dashboard/connect_shopify_settings marketing_subscriptions],
      'mail' => %w[dashboard/mail api/lightek_mail], 'accounting' => %w[dashboard/accounting dashboard/financial_operations],
      'people' => %w[dashboard/people departments employee/users employee/timesheets], 'directory' => %w[dashboard/directory],
      'compliance' => %w[dashboard/compliance], 'community' => %w[dymond_social communities community_ profiles posts storyline_],
      'susu' => %w[susu_ dashboard/susu], 'pwa' => %w[dashboard/pwa],
      'ott' => %w[gatekeeper kitchen_sink channels episodes shows],
      'agency' => %w[dymond_connect dashboard/agencies dashboard/agency_ dashboard/demos demo_requests dashboard/reseller_packages dashboard/hosting_packages resellers connect_management connect_shopify dashboard/connect],
      'nevaeh' => %w[dashboard/nevaeh employee/nevaeh employee/software_library employee/tickets employee/projects nevaehs system_jobs job_items],
      'design' => %w[dashboard/design_studio dashboard/website_designs dashboard/authentication_branding dymond_dash/templates dashboard/blog lightek_blog website_template_inquiries],
      'website' => %w[dashboard/website_settings dymond_dash/pages dymond_dash/sites pages homes abouts architectures]
    }.freeze
    def self.capability(value)
      slug = value.to_s
      return 'studio' if slug.start_with?('studio.', 'blender.')
      return 'messaging' if slug.start_with?('messaging.', 'messages.', 'lightek.messaging.')
      return 'community' if slug.start_with?('community.', 'social.')
      return 'susu' if slug.start_with?('susu.', 'money.')
      'nevaeh'
    end
    def self.for_controller(controller, params = {})
      controller = controller.to_s
      return nil if PUBLIC_BASELINE.include?(controller)
      return nil if controller == 'lightek_website_delivery' && %w[health release].include?((params[:action] || params['action']).to_s)
      return 'pwa' if controller == 'api/nevaeh' && (params[:action] || params['action']).to_s == 'bootstrap'
      if controller == 'dashboard/media_studio' && %w[save_application save_channel schedule remove_program].include?((params[:action] || params['action']).to_s)
        return 'ott'
      end
      return capability(params[:capability] || params['capability']) if controller == 'api/nevaeh' && (params[:capability] || params['capability'])
      if controller == 'api/lightek_pwa'
        action = (params[:action] || params['action']).to_s
        return 'live' if action.start_with?('live_')
        return 'ott' if action.start_with?('ott_')
        return 'studio' if action.start_with?('spatial_') || action.start_with?('asset_')
        return 'community' unless action == 'upload'
        return 'pwa'
      end
      found = PREFIXES.find { |_feature, prefixes| prefixes.any? { |prefix| controller.start_with?(prefix) } }
      found ? found.first : 'website'
    end
    def self.for_path(path)
      value = URI.parse(path.to_s).path
      match = Rails.application.routes.recognize_path(value, method: :get)
      for_controller(match[:controller], match)
    rescue URI::InvalidURIError, ActionController::RoutingError
      nil
    end
  end
end
