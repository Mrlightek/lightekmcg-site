# Existing routes use the same site, audience and membership boundary as the PWA.
class CommunitiesController < ApplicationController
  protect_from_forgery with: :exception
  before_action { response.set_header("Cache-Control", "private, no-store") }
  before_action :set_community, only: %i[show edit update destroy]
  rescue_from LightekCommunity::AccessDenied, LightekPwa::Policy::Denied do |error|
    render json: { error: error.message }, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/communities" }
      format.json { render json: access.communities.order(:name).limit(100).map { |community| presenter.community(community) } }
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/community/#{@community.slug}" }
      format.json { render json: presenter.community(@community) }
    end
  end

  def new
    redirect_to "/lightek/index.html#/communities"
  end

  def edit
    access.manage!(@community)
    redirect_to "/lightek/index.html#/community/#{@community.slug}"
  end

  def create
    result = perform("community_create", community_params.merge("request_key" => SecureRandom.uuid))
    render_result(result, :created)
  end

  def update
    result = perform("community_update", community_params.merge("slug" => @community.slug))
    render_result(result, :ok)
  end

  def destroy
    access.manage!(@community)
    # Community deletion is an owner action; delegated managers may edit members.
    raise LightekCommunity::AccessDenied, "Only the owner can delete this community" unless access.super_admin? || @community.owner_profile_id == current_user.profile&.id
    @community.destroy!
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/communities", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def access
    site = LightekPwa::SiteContext.resolve(request.host)
    LightekPwa::Policy.new(user: current_user, site: site).authorize!("communities")
    @access ||= LightekCommunity::Access.new(user: current_user, site_id: site.id)
  end
  def presenter = LightekCommunity::Presenter.new(access)
  def set_community = @community = access.communities.find(params.expect(:id))
  def community_params = params.require(:community).permit(:name, :description, :visibility, :audience, sections: []).to_h
  def perform(action, payload)
    LightekCommunity::Workers::Pwa.perform(action, payload.merge("user_id" => current_user.id, "site_id" => access.site_id))
  end
  def render_result(result, status)
    respond_to do |format|
      format.html { redirect_to "/lightek/index.html#/community/#{result.fetch(:community).fetch(:slug)}", status: :see_other }
      format.json { render json: result.fetch(:community), status: status }
    end
  end
end
