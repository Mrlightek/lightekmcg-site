scope "/dashboard/workspace/mail-discovery", controller: "dashboard/mail_discovery" do
  get "/", action: :index, as: :dashboard_mail_discovery
  post "/retention", action: :update_retention, as: :dashboard_mail_retention
  post "/matters", action: :create_matter, as: :dashboard_mail_matters
  get "/matters/:id", action: :show, as: :dashboard_mail_matter
  post "/matters/:id/hold", action: :hold, as: :hold_dashboard_mail_matter
  delete "/matters/:id/hold", action: :release, as: :release_dashboard_mail_matter
  post "/matters/:id/reviewers", action: :grant, as: :grant_dashboard_mail_matter
  delete "/matters/:id/reviewers/:reviewer_id", action: :revoke, as: :revoke_dashboard_mail_matter
  post "/matters/:id/search", action: :search, as: :search_dashboard_mail_matter
  post "/matters/:id/export", action: :export, as: :export_dashboard_mail_matter
  post "/matters/:id/drives", action: :hold_drive, as: :hold_dashboard_discovery_drive
  delete "/matters/:id/drives", action: :release_drive, as: :release_dashboard_discovery_drive
  post "/matters/:id/drives/search", action: :search_drive, as: :search_dashboard_discovery_drive
  post "/matters/:id/drives/export", action: :export_drive, as: :export_dashboard_discovery_drive
  post "/drive-retention", action: :update_drive_retention, as: :dashboard_discovery_drive_retention
  post "/matters/:id/channels", action: :hold_channel, as: :hold_dashboard_discovery_channel
  delete "/matters/:id/channels", action: :release_channel, as: :release_dashboard_discovery_channel
  post "/matters/:id/channels/search", action: :search_channel, as: :search_dashboard_discovery_channel
  post "/matters/:id/channels/export", action: :export_channel, as: :export_dashboard_discovery_channel
end
