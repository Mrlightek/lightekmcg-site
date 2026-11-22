# frozen_string_literal: true

module Studio
  module Animation
    class AssetsController < BaseController
      include StudioBlobStreaming

      before_action :find_asset, only: %i[show update destroy file preview]

      def index
        @library = @assets.or(@starters).with_attached_file.with_attached_native.with_attached_proxy.order(:name)
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
        attachment = @asset.animation_role? ? @asset.file : @asset.native
        raise ActiveRecord::RecordNotFound unless attachment.attached?
        response.set_header("Content-Security-Policy", "sandbox")
        response.set_header("X-Content-Type-Options", "nosniff")
        disposition = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: attachment.filename.to_s)
        stream_blob(attachment.blob, disposition: disposition)
      end

      def preview
        if request.get? || request.head?
          raise ActiveRecord::RecordNotFound unless proxy_ready?(@asset)
          stream_blob(@asset.proxy.blob)
          return
        end

        raise ActiveRecord::RecordNotFound unless native_upload?(@asset)
        @asset.with_lock do
          job = preview_record(@asset)
          unless proxy_ready?(@asset) || (job["status"] == "queued" && job["requested_at"].to_i > 5.minutes.ago.to_i)
            blob_id = @asset.file.blob.id
            @asset.update!(metadata: @asset.metadata.merge("animation_preview" => {
              "blob_id" => blob_id, "status" => "queued", "requested_at" => Time.current.to_i
            }))
            raise ArgumentError, "The preview worker is unavailable" unless StudioAnimationPreviewJob.perform_later(@asset.id, blob_id)
          end
        end
        render json: asset_data(@asset), status: :accepted
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

      def native_upload?(asset)
        asset.animation_role? && asset.dimension_mode == "3d" &&
          %w[blend fbx].include?(asset.file.filename.extension.downcase)
      end

      def preview_record(asset)
        result = asset.metadata.fetch("animation_preview", {})
        result["blob_id"] == asset.file.blob.id ? result : {}
      end

      def proxy_ready?(asset)
        asset.proxy.attached? && (!asset.animation_role? || preview_record(asset)["status"] == "ready")
      end

      def preview_status(asset)
        record = preview_record(asset)
        return "failed" if record["status"] == "queued" && record["requested_at"].to_i <= 5.minutes.ago.to_i
        record["status"]
      end

      def asset_data(asset)
        attachment = asset.animation_role? ? asset.file : asset.native
        asset.as_json(only: %i[id name animation_role]).merge(
          dimension_mode: asset.animation_role? ? asset.dimension_mode : "3d", starter: asset.animation_role.nil?,
          file_url: file_studio_animation_asset_path(asset, site_id: @site.id, v: attachment.blob.id),
          filename: attachment.filename.to_s,
          preview_url: (preview_studio_animation_asset_path(asset, site_id: @site.id, v: asset.proxy.blob.id) if proxy_ready?(asset)),
          preview_request_url: (preview_studio_animation_asset_path(asset, site_id: @site.id) if native_upload?(asset)),
          preview_status: (preview_status(asset) if native_upload?(asset))
        )
      end
    end
  end
end
