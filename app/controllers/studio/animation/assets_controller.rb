# frozen_string_literal: true

module Studio
  module Animation
    class AssetsController < BaseController
      include StudioBlobStreaming

      before_action :find_asset, only: %i[show update destroy file preview]

      def index
        @library = @assets.or(@starters).with_attached_file.with_attached_native.order(:name)
        respond_to do |format|
          format.html
          format.json { render json: @library.map { |asset| asset_data(asset) } }
        end
      end

      def show
        respond_to do |format|
          format.html
          format.json { render json: asset_data(@asset) }
        end
      end

      def file
        attachment = @asset.animation_source
        raise ActiveRecord::RecordNotFound unless attachment.attached?
        response.set_header("Content-Security-Policy", "sandbox")
        response.set_header("X-Content-Type-Options", "nosniff")
        disposition = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: attachment.filename.to_s)
        stream_blob(attachment.blob, disposition: disposition)
      end

      def preview
        raise ActiveRecord::RecordNotFound unless @asset.native_animation_model?
        if params[:file] == "1"
          raise ActiveRecord::RecordNotFound unless request.get? || request.head?
          record = @asset.studio_animation_previews.find_by!(variant_digest: params[:key], status: "ready")
          raise ActiveRecord::RecordNotFound unless record.settings["blob_id"] == @asset.animation_source.blob.id && record.file.attached?
          stream_blob(record.file.blob)
          return
        end

        if request.post?
          @asset.with_lock do
            raise ActiveRecord::RecordNotFound unless @asset.native_animation_model?
            settings = StudioAnimationPreview.settings_for(@asset, params)
            @preview = @asset.studio_animation_previews.find_or_initialize_by(variant_digest: StudioAnimationPreview.key_for(settings))
            if @preview.new_record? || @preview.preview_status == "failed"
              token = SecureRandom.uuid
              @preview.update!(settings: settings, status: "queued", attempt_token: token)
              raise ArgumentError, "The preview worker is unavailable" unless StudioAnimationPreviewJob.perform_later(@preview.id, token)
            end
          end
        else
          settings = StudioAnimationPreview.settings_for(@asset, params)
          @preview = @asset.studio_animation_previews.find_by(variant_digest: StudioAnimationPreview.key_for(settings))
        end
        render json: preview_data(@preview), status: @preview&.preview_status == "queued" ? :accepted : :ok
      rescue ArgumentError, ActiveJob::EnqueueError => error
        render json: { error: error.message }, status: :unprocessable_entity
      end

      def create
        @asset = @assets.new(owner: current_user, site: @site, request_key: SecureRandom.uuid, status: "ready")
        save_asset(:created)
      end

      def update
        save_asset(:ok)
      end

      def destroy
        @asset.destroy!
        respond_to do |format|
          format.html { redirect_to studio_animation_assets_path(site_id: @site.id), status: :see_other }
          format.json { head :no_content }
        end
      end

      private

      def find_asset
        @asset = (%w[show file preview].include?(action_name) ? @assets.or(@starters) : @assets).find(params[:id])
      end

      def save_asset(status)
        attrs = params.expect(asset: %i[name animation_role dimension_mode file])
        @asset.assign_attributes(attrs)
        role = @asset.animation_role
        raise ArgumentError, "Select an asset role" if role.blank?
        @asset.dimension_mode = nil if role == "audio"
        @asset.dimension_mode = "2d" if role == "viseme"
        extension = @asset.file.filename.extension.to_s.downcase if @asset.file.attached?
        @asset.kind = if role == "audio"
          "audio"
        elsif @asset.dimension_mode == "3d"
          extension == "blend" ? "blend" : "glb"
        else
          "image"
        end
        @asset.save!
        respond_to do |format|
          format.html { redirect_to studio_animation_asset_path(@asset, site_id: @site.id), status: :see_other }
          format.json { render json: asset_data(@asset), status: status }
        end
      rescue ArgumentError, ActiveRecord::RecordInvalid => error
        invalid(error, @asset.persisted? ? studio_animation_asset_path(@asset, site_id: @site.id) : studio_animation_assets_path(site_id: @site.id))
      end

      def preview_data(record)
        data = { preview_status: record&.preview_status || "missing", clips: [] }
        if record&.status == "ready" && record.file.attached?
          data[:preview_url] = preview_studio_animation_asset_path(@asset, site_id: @site.id,
            key: record.variant_digest, file: 1)
          data[:preview_kind] = "static"
          data[:evaluated_frame] = record.settings.fetch("pose_frame", 1)
        end
        data
      end

      def asset_data(asset)
        attachment = asset.animation_source
        asset.as_json(only: %i[id name animation_role]).merge(
          dimension_mode: asset.animation_role? ? asset.dimension_mode : "3d", starter: asset.animation_role.nil?,
          file_url: file_studio_animation_asset_path(asset, site_id: @site.id, v: attachment.blob.id),
          source_revision: attachment.blob.id, filename: attachment.filename.to_s,
          preview_request_url: (preview_studio_animation_asset_path(asset, site_id: @site.id) if asset.native_animation_model?)
        )
      end
    end
  end
end
