# frozen_string_literal: true
module Studio
  class PwaAccess
    def initialize(payload)
      @user = User.find(payload.fetch("user_id"))
      @site_id = payload["site_id"]
    end
    attr_reader :user, :site_id
    def projects
      library = StudioProject.shared_studio_projects
      return library if user.role.to_s == "super_admin"
      base = library.where(site_id: site_id)
      policy = LightekPwa::Policy.new(user: user, site: DymondSite::Site.find(site_id)) if site_id
      return base if policy && %w[admin editor].include?(policy.role)
      base.where(owner_id: user.id)
    end
    def scene!(id) = StudioScene.where(studio_project_id: projects.select(:id)).find(id)
  end
end
