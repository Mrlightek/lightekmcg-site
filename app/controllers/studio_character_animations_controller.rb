# frozen_string_literal: true

class StudioCharacterAnimationsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :character_workspace
  before_action :find_operation, except: :create
  before_action { response.set_header("Cache-Control", "private, no-store") }

  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  rescue_from LightekPwa::Policy::Denied do |error|
    render plain: error.message, status: :forbidden
  end

  def create
    operation = @pipeline.launch(animation_params)
    redirect_to studio_character_animation_path(operation, site_id: @site.id), status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to studio_pipeline_path(site_id: @site.id, anchor: "character-animation"), alert: error.message, status: :see_other
  end

  def show
    @video = pipeline_file("video")
    @animated = pipeline_file("package")
    render layout: false
  end

  def retry_login
    update_operation { @pipeline.retry_login(@operation) }
  end

  def render_only
    update_operation { @pipeline.render_only(@operation, animation_params) }
  end

  def preview
    video = pipeline_file("video")
    raise ActiveRecord::RecordNotFound unless video
    redirect_to rails_storage_proxy_path(video.blob, disposition: params[:download] == "1" ? "attachment" : "inline")
  end

  private

  def character_workspace
    @site = Studio::Broadcasting::Access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site
    @pipeline = Studio::Pipeline::CharacterAnimation.new(Studio::Pipeline::Access.new(current_user, @site))
  end

  def find_operation
    @operation = @pipeline.operations.find(params[:id])
  end

  def pipeline_file(kind) = Studio::Pipeline::CharacterAnimation.file(@operation, kind)

  def animation_params
    params.expect(character_animation: %i[gender height muscle animation animation_id frames resolution]).to_h.stringify_keys
  end

  def update_operation
    yield
    redirect_to studio_character_animation_path(@operation, site_id: @site.id), status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to studio_character_animation_path(@operation, site_id: @site.id), alert: error.message, status: :see_other
  end
end
