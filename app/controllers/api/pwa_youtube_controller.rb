module Api
  class PwaYoutubeController < ApplicationController
    allow_unauthenticated_access only: :source
    skip_authorization_check
    protect_from_forgery with: :exception
    before_action :context, except: :source
    before_action { response.set_header('Cache-Control', 'private, no-store') }
    rescue_from LightekPwa::Policy::Denied do |e|
      render json: {error: e.message}, status: :forbidden
    end
    rescue_from LightekPwa::YoutubePublishing::Unavailable, ActiveRecord::RecordInvalid do |e|
      render json: {error: e.message}, status: :unprocessable_entity
    end
    def show
      upload = LightekPwa::YoutubeUpload.find_by(post: @post)
      render json: {upload: upload&.summary, post: {id: @post.id, title: @post.title},
        enabled: LightekPwa::YoutubePublishing.central_enabled?(@site) || LightekReservations::Federation::Client.config(@site).present?}
    end
    def create
      upload = LightekPwa::YoutubePublishing.submit!(post: @post, actor: current_user, consent: params[:consent], made_for_kids: params[:made_for_kids])
      render json: {upload: upload.summary}
    end
    def withdraw
      upload = LightekPwa::YoutubeUpload.find_by!(post: @post)
      LightekPwa::YoutubePublishing.request_withdrawal!(upload)
      render json: {upload: upload.summary}
    end
    def source
      # A bounded, expiring original-only grant. A source-domain login does not
      # widen it to other files or private posts. No arbitrary path/URL accepted.
      blob = LightekPwa::YoutubePublishing.source_blob!(params.require(:grant))
      response.set_header('Content-Type', blob.content_type)
      response.set_header('Content-Length', blob.byte_size.to_s)
      response.set_header('Content-Disposition', 'attachment')
      response.set_header('X-Content-Type-Options', 'nosniff')
      self.response_body = Enumerator.new { |out| blob.download { |chunk| out << chunk } }
    end
    private
    def context
      @site = LightekPwa::SiteContext.resolve(request.host)
      LightekPwa::Policy.new(user: current_user, site: @site).authorize!
      @post = Post.where(site: @site, user: current_user).find(params.require(:post_id))
    end
  end
end
