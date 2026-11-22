# frozen_string_literal: true

module Studio
  module Animation
    class RendersController < BaseController
      include StudioBlobStreaming

      before_action :find_scene
      before_action :find_render, except: %i[index create]

      def index
        expire_renders
        render json: @scene.studio_scene_renders.order(id: :desc).map { |item| render_data(item) }
      end

      def show
        @render.expire_if_stale!
        respond_to do |format|
          format.html
          format.json { render json: render_data(@render) }
        end
      end

      def create
        submit
      end

      def retry_render
        submit(source: @render)
      end

      def destroy
        @scene.with_lock do
          @render.expire_if_stale!
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

      class SubmissionConflict < StandardError; end

      def submit(source: nil)
        request_id = params[:request_id].to_s.downcase
        raise ArgumentError, "A valid render request ID is required." unless StudioSceneRender::REQUEST_ID_FORMAT.match?(request_id)
        revision = requested_revision unless source
        created = false
        @scene.with_lock do
          if (existing = @scene.studio_scene_renders.find_by(request_id: request_id))
            unless existing.retry_of_id == source&.id && (source || existing.scene_revision == revision)
              raise SubmissionConflict, "This render request ID belongs to a different submission."
            end
            existing.expire_if_stale!
            @render = existing
          else
            expire_renders
            raise SubmissionConflict, "This scene already has a video render in progress." if @scene.studio_scene_renders.active.exists?
            @render = source ? retry_snapshot(source, request_id) : scene_snapshot(revision, request_id)
            created = true
          end
        end
        enqueue if created
        respond_to do |format|
          format.html { redirect_to studio_animation_scene_render_path(@scene, @render, site_id: @site.id), status: :see_other }
          format.json { render json: render_data(@render), status: created ? :accepted : :ok }
        end
      rescue SubmissionConflict => error
        respond_to do |format|
          format.html { redirect_to studio_animation_scene_path(@scene, site_id: @site.id), alert: error.message, status: :see_other }
          format.json { render json: { error: error.message }, status: :conflict }
        end
      rescue ArgumentError, ActiveRecord::RecordInvalid => error
        invalid(error, studio_animation_scene_path(@scene, site_id: @site.id))
      end

      def requested_revision
        raw = params[:lock_version].to_s
        raise ArgumentError, "A saved scene revision is required." unless /\A[0-9]{1,10}\z/.match?(raw)
        raw.to_i
      end

      def scene_snapshot(revision, request_id)
        unless revision == @scene.lock_version
          raise SubmissionConflict, "The scene has changed since you saved it. Reload to render the latest revision."
        end
        manifest, blobs = Manifest.new(@assets.or(@starters)).build(@scene.scene_spec)
        @scene.studio_scene_renders.create!(request_id: request_id, scene_revision: revision,
          manifest: manifest, inputs: blobs.values)
      end

      def retry_snapshot(source, request_id)
        source.reload
        raise SubmissionConflict, "Only a failed render can be retried." unless source.status == "failed"
        @scene.studio_scene_renders.create!(request_id: request_id, scene_revision: source.scene_revision,
          retry_of_id: source.id, manifest: source.manifest, inputs: source.inputs.blobs.to_a)
      end

      def expire_renders
        @scene.studio_scene_renders.active.find_each(&:expire_if_stale!)
      end

      def enqueue
        job = StudioSceneRenderJob.perform_later(@render.id)
        raise ActiveJob::EnqueueError, "The video worker queue is unavailable" unless job
      rescue StandardError => error
        Rails.logger.error("Studio scene render #{@render.id} enqueue: #{error.class}")
        @render.with_lock do
          if @render.status == "queued"
            @render.mark_failed!("The video worker queue is unavailable. Retry this render to queue the saved snapshot again.")
          end
        end
      end

      def find_scene = @scene = @scenes.find(params[:scene_id])
      def find_render = @render = @scene.studio_scene_renders.find(params[:id])

      def render_data(item)
        data = item.as_json(only: %i[id status progress failed_phase error_message created_at])
        if item.status == "failed"
          data["retry_url"] = retry_studio_animation_scene_render_path(@scene, item, site_id: @site.id)
        elsif item.status == "completed"
          data["video_url"] = video_studio_animation_scene_render_path(@scene, item, site_id: @site.id)
          data["download_url"] = video_studio_animation_scene_render_path(@scene, item, site_id: @site.id, download: 1)
        end
        data
      end
    end
  end
end
