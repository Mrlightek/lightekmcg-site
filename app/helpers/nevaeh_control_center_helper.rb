# frozen_string_literal: true
module NevaehControlCenterHelper
  def nevaeh_home_path
    current_user.role == "client" ? main_app.dashboard_client_home_path : dymond_dash.root_path
  end

  def nevaeh_navigation_defaults
    item = ->(id, label, path, icon, group = "Workspaces") { {"id" => id, "label" => label, "path" => path, "icon" => icon, "group" => group} }
    rows = [item.call("overview", "Overview", nevaeh_home_path, "ti-layout-dashboard"),
      item.call("business", "Business", main_app.dashboard_business_hub_path, "ti-building-store"),
      item.call("compliance", "Legal & Compliance", main_app.dashboard_compliance_path, "ti-scale"),
      item.call("accounting", "Books & Accounting", main_app.dashboard_accounting_path, "ti-report-money"),
      item.call("directory", "Directory & Access", main_app.dashboard_directory_path, "ti-shield-lock"),
      item.call("people", "People & Access", main_app.dashboard_people_path, "ti-users-group"),
      item.call("reservations", "Reservations", main_app.dashboard_reservations_path, "ti-calendar-event"),
      item.call("rooms", "Rooms & Guests", main_app.dashboard_rooms_path, "ti-users"),
      item.call("my-reservations", "My Reservations", main_app.my_reservations_path, "ti-ticket"),
      item.call("agency", "Agency & Marketing", main_app.dashboard_agency_reports_path, "ti-chart-dots"),
      item.call("design", "Design & Content", main_app.dashboard_website_designs_path, "ti-palette"),
      item.call("journal", "Journal & Articles", main_app.dashboard_blog_index_path, "ti-article"),
      item.call("mail", "Communications", main_app.dashboard_mail_path, "ti-mail")]
    if current_user.role.in?(%w[admin super_admin]) || current_user.can_access_feature?("studio")
      rows << item.call("studio", "Studio & Broadcasting", main_app.dashboard_media_studio_path, "ti-video")
    end
    rows << item.call("servers", "Servers & Applications", main_app.dashboard_servers_path, "ti-server")
    if current_user.can_access_feature?("commerce_workspace")
      rows << item.call("commerce", "Commerce", main_app.dashboard_commerce_path, "ti-shopping-cart")
      rows << item.call("shipping", "Shipping & Fulfillment", main_app.dashboard_shipping_path, "ti-truck-delivery")
    end
    if current_user.role.in?(%w[super_admin white_label]) || (current_user.role == "admin" && LightekAgency::PackagePolicy.runtime_accounts.exists?)
      rows << item.call("reseller-packages", "Reseller packages", main_app.dashboard_reseller_packages_path, "ti-packages")
    end
    if current_user.role.in?(%w[super_admin white_label])
      rows << item.call("demos", "Client demos", main_app.dashboard_demos_path, "ti-flask")
      rows << item.call("connect", "Lightek Connect", main_app.dashboard_connect_path, "ti-plug-connected")
      rows << item.call("white-label", "White Label Agencies", main_app.dashboard_agencies_path, "ti-brand-asana")
    end
    if LightekPwa::Policy.administration_available_for?(current_user)
      rows << item.call("pwa", "PWA Administration", main_app.dashboard_pwa_path, "ti-device-mobile")
    end
    if current_user.role == "super_admin"
      rows += [item.call("infrastructure", "Infrastructure", main_app.dashboard_infrastructure_path, "ti-server"),
        item.call("finance", "Finance", main_app.dashboard_bank_path, "ti-wallet"),
        item.call("vault", "Vault", main_app.dashboard_vault_path, "ti-lock")]
    end
    if current_user.employee? && can?(:read, Marlon::Ticket)
      rows << item.call("nevaeh", "Nevaeh Control Center", main_app.employee_nevaeh_control_center_path, "ti-brain", "Nevaeh")
      if can?(:manage, NevaehWorkflow)
        rows << item.call("factory", "Digital Factory", main_app.employee_nevaeh_factory_path, "ti-building-factory", "Nevaeh")
        rows << item.call("software-library", "Software Library", main_app.employee_software_library_path, "ti-books", "Nevaeh")
      end
      rows << item.call("capabilities", "Capabilities", main_app.employee_nevaeh_capabilities_path, "ti-box", "Nevaeh")
      rows << item.call("tickets", "Support Tickets", main_app.employee_tickets_path, "ti-ticket", "Nevaeh")
      rows << item.call("new-ticket", "New Ticket", main_app.new_employee_ticket_path, "ti-plus", "Nevaeh") if can?(:create, Marlon::Ticket)
    end
    rows << item.call("settings", "Settings", main_app.dashboard_settings_home_path, "ti-settings", "System")
    rows
  end

  def nevaeh_dashboard_breadcrumbs(page_label:)
    home = nevaeh_home_path
    entries = nevaeh_sidebar_entries.reject { |entry| entry['hidden'] }
    entries += [{"path" => main_app.dashboard_live_path, "label" => "Live Studio"},
      {"path" => main_app.dashboard_session_media_path, "label" => "Room service"}]
    current = request.path.sub(%r{/+$}, '')
    selected = entries.select do |entry|
      path = entry['path'].to_s.split('?').first.to_s.sub(%r{/+$}, '')
      path.start_with?('/') && !path.start_with?('//') && path != home.sub(%r{/+$}, '') &&
        (current == path || current.start_with?(path + '/'))
    end.max_by { |entry| entry['path'].to_s.split('?').first.length }
    rows = [{label: 'Dashboard', path: home}]
    if selected
      target = selected['path'].to_s
      if defined?(@site) && @site&.id
        target += (target.include?('?') ? '&' : '?') + 'site_id=' + ERB::Util.url_encode(@site.id.to_s)
      end
      rows << {label: selected['label'], path: current == selected['path'].to_s.split('?').first.sub(%r{/+$}, '') ? nil : target}
    end
    rows << {label: page_label, path: nil} unless rows.last[:path].nil?
    rows
  end

  def package_navigation(entries)
    return entries unless defined?(LightekAgency::PackagePolicy) && current_user.role != 'super_admin'
    entries.select { |entry| LightekAgency::PackagePolicy.allowed?(current_user, LightekAgency::PackageFeatures.for_path(entry['path'])) }
  end

  def nevaeh_sidebar_entries
    unless NevaehWorkspacePreference.table_exists?
      return package_navigation(nevaeh_navigation_defaults)
    end
    entries = NevaehIntelligences::WorkspaceNavigation.entries(user: current_user, defaults: nevaeh_navigation_defaults)
    package_navigation(entries.map { |entry| entry['id'] == 'overview' && current_user.role == 'client' ? entry.merge('path' => nevaeh_home_path) : entry })
  end
end
