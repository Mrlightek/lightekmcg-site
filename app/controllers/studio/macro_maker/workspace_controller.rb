module Studio
  module MacroMaker
    class WorkspaceController < ApplicationController
      helper FormHelper
      protect_from_forgery with: :exception
      before_action :load_workspace
      rescue_from ActiveRecord::RecordNotFound do
        head :not_found
      end

      private

      def load_workspace
        context = request.env[BaseController::CONTEXT_KEY]
        if context
          @site, @user = context.values_at(:site, :user)
        else
          @site = LightekPwa::SiteContext.resolve(request.host)
          @user = current_user
          LightekPwa::Policy.new(user: @user, site: @site).authorize!("studio")
        end
        unless @site.is_a?(DymondSite::Site) && @site.persisted? && @user.is_a?(User) && @user.persisted?
          return head :forbidden
        end

        response.headers["Cache-Control"] = "private, no-store"
        @catalog_options = {
          engine_adapters: context&.fetch(:engine_adapters, nil) || Operation::EngineAdapter.configured,
          built_in_directory: Rails.root.join("config/studio/operations"),
          command_schema_directory: Rails.root.join("config/studio/command_schemas")
        }
        @store = CompositionStore.new(site: @site, user: @user, catalog_options: @catalog_options)
      rescue LightekPwa::Policy::Denied
        head :forbidden
      end

      def authorize_editor_access
        return if LightekPwa::Policy.sites_for(@user).exists?(id: @site.id)

        head :forbidden
      end

      def requested_surface
        surface = request.query_parameters["surface"]
        raise ActiveRecord::RecordNotFound if surface && !%w[image motion].include?(surface)

        surface
      end
    end
  end
end
