# frozen_string_literal: true

module Studio
  module Pipeline
    class Access
      attr_reader :user, :site

      def initialize(user, site)
        @user, @site = user, site
        raise LightekPwa::Policy::Denied, "Workspace access is unavailable" unless
          user && site && LightekPeople::LifecycleAccess.active?(user) &&
          LightekPwa::Policy.sites_for(user).exists?(id: site.id)

        policy = LightekPwa::Policy.new(user: user, site: site)
        policy.authorize_admin!("studio")
        policy.authorize!("studio")
      end

      def assets
        StudioAsset.for_actor(Studio::PwaAccess.new("user_id" => user.id, "site_id" => site.id)).where(site: site)
      end

      def cards
        assets.where("metadata ? 'pipeline_stage'")
      end

      def renders
        StudioOperation.where(capability: Render::CAPABILITY,
          studio_project_id: StudioProject.where(owner: user, site: site))
      end
    end
  end
end
