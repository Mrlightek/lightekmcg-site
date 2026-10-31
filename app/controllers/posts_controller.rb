# The legacy HTML/JSON routes share the PWA's policy and mutation workers.
class PostsController < ApplicationController
  protect_from_forgery with: :exception
  before_action { response.set_header("Cache-Control", "private, no-store") }
  before_action :set_post, only: %i[show edit update destroy]
  rescue_from LightekCommunity::AccessDenied do |error|
    render json: { error: error.message }, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    @posts = access.posts.order(id: :desc).limit(100)
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/home" }
      format.json { render json: @posts.map { |post| presenter.post(post) } }
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/post/#{@post.id}" }
      format.json { render json: presenter.post(@post) }
    end
  end

  def new
    redirect_to "/lightek/index.html#/create"
  end

  def edit
    raise LightekCommunity::AccessDenied, "Only the author can edit this post" unless access.super_admin? || @post.user_id == current_user.id
    redirect_to "/lightek/index.html#/post/#{@post.id}"
  end

  def create
    result = perform("post_create", post_params.merge("request_key" => SecureRandom.uuid))
    render_result(result, :created)
  end

  def update
    result = perform("post_update", post_params.merge("post_id" => @post.id))
    render_result(result, :ok)
  end

  def destroy
    perform("post_delete", "post_id" => @post.id)
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/home", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def access
    @access ||= LightekCommunity::Access.new(user: current_user, site_id: LightekPwa::SiteContext.resolve(request.host).id)
  end
  def presenter = LightekCommunity::Presenter.new(access)
  def set_post = @post = access.posts.find(params.expect(:id))
  def post_params = params.require(:post).permit(:title, :content, :kind, :visibility, :audience, :slug).to_h
  def perform(action, payload)
    LightekCommunity::Workers::Pwa.perform(action, payload.merge("user_id" => current_user.id, "site_id" => access.site_id))
  end
  def render_result(result, status)
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/post/#{result.fetch(:post).fetch(:id)}", status: :see_other }
      format.json { render json: result.fetch(:post), status: status }
    end
  end
end
