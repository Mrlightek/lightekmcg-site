# frozen_string_literal: true
module Studio
  class PwaAccess
    def initialize(payload)
      @user = User.find(payload.fetch("user_id"))
      @site_id = payload["site_id"]
    end
    attr_reader :user, :site_id
    def projects
      return StudioProject.all if user.role.to_s == "super_admin"
      base = StudioProject.where(site_id: site_id)
      base.where(owner_id: user.id)
    end
    def scene!(id) = StudioScene.where(studio_project_id: projects.select(:id)).find(id)
  end
end
