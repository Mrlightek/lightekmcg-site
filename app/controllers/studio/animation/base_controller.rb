# frozen_string_literal: true

module Studio
  module Animation
    class BaseController < ApplicationController
      layout "studio_animation"
      protect_from_forgery with: :exception
      before_action :animation_workspace
      before_action { response.set_header("Cache-Control", "private, no-store") }

      rescue_from ActiveRecord::RecordNotFound do
        head :not_found
      end
      rescue_from LightekPwa::Policy::Denied do |error|
        render plain: error.message, status: :forbidden
      end

      private

      def animation_workspace
        host_site = DymondSite::Site.find_by(host: request.host.downcase)
        @site = if host_site && (params[:site_id].blank? || params[:site_id].to_s == host_site.id.to_s)
          host_site
        else
          Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
        end
        raise ActiveRecord::RecordNotFound unless @site
        LightekPwa::Policy.new(user: current_user, site: @site).authorize!("studio")
        @projects = StudioProject.where(owner: current_user, site: @site, animation_workspace: true)
        @scenes = StudioScene.animation_scenes.where(studio_project: @projects)
        owned_assets = StudioAsset.where(owner: current_user, site: @site)
        @assets = owned_assets.animation_assets
        @starters = owned_assets.animation_starters
      end

      def invalid(error, destination)
        respond_to do |format|
          format.html { redirect_to destination, alert: error.message, status: :see_other }
          format.json { render json: { error: error.message }, status: :unprocessable_entity }
        end
      end
    end
  end
end
