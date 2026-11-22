# frozen_string_literal: true

module Studio
  module Animation
    class RendersController < BaseController
      include StudioBlobStreaming

      before_action :find_scene
      before_action :find_render, except: %i[index create]

      def index
        render json: @scene.studio_scene_renders.order(id: :desc).map { |item| render_data(item) }
      end

      def show
        respond_to do |format|
          format.html
          format.json { render json: render_data(@render) }
        end
      end

      def create
        @scene.with_lock do
          raise ArgumentError, "This scene already has a video render in progress" if @scene.studio_scene_renders.active.exists?
          manifest, blobs = Manifest.new(@assets.or(@starters)).build(@scene.scene_spec)
          @render = @scene.studio_scene_renders.new(manifest: manifest, inputs: blobs.values)
          @render.save!
        end
        enqueue
        respond_to do |format|
          format.html { redirect_to studio_animation_scene_render_path(@scene, @render, site_id: @site.id), status: :see_other }
          format.json { render json: render_data(@render), status: :accepted }
        end
      rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveJob::EnqueueError => error
        invalid(error, studio_animation_scene_path(@scene, site_id: @site.id))
      end

      def destroy
        @render.with_lock do
          raise ArgumentError, "Wait for the render to finish before deleting it" if @render.active?
          @render.destroy!
        end
        respond_to do |format|
          format.html { redirect_to studio_animation_scene_path(@scene, site_id: @site.id), status: :see_other }
          format.json { head :no_content }
        end
      rescue ArgumentError => error
        invalid(error, studio_animation_scene_render_path(@scene, @render, site_id: @site.id))
      end

      def video
        raise ActiveRecord::RecordNotFound unless @render.status == "completed" && @render.video.attached?
        disposition = params[:download] == "1" ? %Q(attachment; filename="scene-#{@render.id}.mp4") : "inline"
        stream_blob(@render.video.blob, disposition: disposition)
      end

      private

      def enqueue
        job = StudioSceneRenderJob.perform_later(@render.id)
        raise ActiveJob::EnqueueError, "The video worker queue is unavailable" unless job
      rescue StandardError => error
        @render.with_lock do
          if @render.status == "queued"
            @render.update!(status: "failed", error_message: "The video worker queue is unavailable.")
          end
        end
        raise ActiveJob::EnqueueError, "The video worker queue is unavailable", cause: error
      end

      def find_scene = @scene = @scenes.find(params[:scene_id])
      def find_render = @render = @scene.studio_scene_renders.find(params[:id])

      def render_data(item)
        data = item.as_json(only: %i[id status progress error_message created_at])
        if item.status == "completed"
          data["video_url"] = video_studio_animation_scene_render_path(@scene, item, site_id: @site.id)
          data["download_url"] = video_studio_animation_scene_render_path(@scene, item, site_id: @site.id, download: 1)
        end
        data
      end
    end
  end
end
