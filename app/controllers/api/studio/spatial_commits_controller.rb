# frozen_string_literal: true
module Api
  module Studio
    class SpatialCommitsController < ApplicationController
      allow_unauthenticated_access only: :create
      skip_forgery_protection only: :create
      def create
        secret=::Studio::Spatial::Runtime.fetch("STUDIO_SPATIAL_SECRET").to_s
        supplied=request.headers["Authorization"].to_s.delete_prefix("Bearer ")
        return head :unauthorized unless secret.length>=32 && ActiveSupport::SecurityUtils.secure_compare(secret,supplied)
        access=::Studio::PwaAccess.new("user_id"=>params.require(:user_id),"site_id"=>params[:site_id])
        site=DymondSite::Site.find(params.require(:site_id))
        LightekPwa::Policy.new(user:access.user,site:site).authorize!("studio")
        render json: ::Studio::Spatial::Commit.call(access,params.require(:scene_id),params.require(:command).to_unsafe_h)
      rescue ArgumentError,ActiveRecord::RecordNotFound,LightekPwa::Policy::Denied => error
        render json:{error:error.message},status: :conflict
      end
    end
  end
end
