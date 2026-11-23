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
end
