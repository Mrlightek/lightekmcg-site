# frozen_string_literal: true
module NevaehControlCenterHelper
  def nevaeh_navigation_defaults
    item = ->(id, label, path, icon, group = "Workspaces") { {"id" => id, "label" => label, "path" => path, "icon" => icon, "group" => group} }
    rows = [item.call("overview", "Overview", dymond_dash.root_path, "ti-layout-dashboard"),
      item.call("business", "Business", main_app.dashboard_business_hub_path, "ti-building-store"),
      item.call("agency", "Agency & Marketing", main_app.dashboard_agency_reports_path, "ti-chart-dots"),
      item.call("design", "Design & Content", main_app.dashboard_website_designs_path, "ti-palette"),
      item.call("mail", "Communications", main_app.dashboard_mail_path, "ti-mail")]
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
      rows << item.call("capabilities", "Capabilities", main_app.employee_nevaeh_capabilities_path, "ti-box", "Nevaeh")
      rows << item.call("tickets", "Support Tickets", main_app.employee_tickets_path, "ti-ticket", "Nevaeh")
      rows << item.call("new-ticket", "New Ticket", main_app.new_employee_ticket_path, "ti-plus", "Nevaeh") if can?(:create, Marlon::Ticket)
    end
    rows << item.call("settings", "Settings", main_app.dashboard_settings_home_path, "ti-settings", "System")
    rows
  end

  def nevaeh_sidebar_entries
    return nevaeh_navigation_defaults unless NevaehWorkspacePreference.table_exists?
    NevaehIntelligences::WorkspaceNavigation.entries(user: current_user, defaults: nevaeh_navigation_defaults)
  end
end
