module Api
  class PwaNetworkController < ApplicationController
    allow_unauthenticated_access only: :show
    skip_authorization_check
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    def show
      site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: nil, site: site).authorize!('home')
      raise ActiveRecord::RecordNotFound unless site.tenant_type == 'User'
      access = LightekCommunity::Access.new(user: nil, site_id: site.id)
      post = access.posts.where(parent_id: nil, community_id: nil, user_id: site.tenant_id, visibility: 'public', audience: 'everyone').find(params.require(:id))
      raise ActiveRecord::RecordNotFound if post.metadata['remote_content']
      response.set_header('Access-Control-Allow-Origin', '*')
      response.set_header('Cache-Control', 'public, max-age=15')
      render json: LightekCommunity::Presenter.new(access).post(post)
    end
  end
end
