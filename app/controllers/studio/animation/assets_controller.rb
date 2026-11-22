# frozen_string_literal: true

module Studio
  module Animation
    class AssetsController < BaseController
      include StudioBlobStreaming

      before_action :find_asset, only: %i[show update destroy file]

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
        attachment = @asset.animation_role? ? @asset.file : @asset.native
        raise ActiveRecord::RecordNotFound unless attachment.attached?
        response.set_header("Content-Security-Policy", "sandbox")
        response.set_header("X-Content-Type-Options", "nosniff")
        disposition = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: attachment.filename.to_s)
        stream_blob(attachment.blob, disposition: disposition)
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
        @asset = (%w[show file].include?(action_name) ? @assets.or(@starters) : @assets).find(params[:id])
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

      def asset_data(asset)
        asset.as_json(only: %i[id name animation_role]).merge(
          dimension_mode: asset.animation_role? ? asset.dimension_mode : "3d", starter: asset.animation_role.nil?,
          file_url: file_studio_animation_asset_path(asset, site_id: @site.id), filename: (asset.animation_role? ? asset.file : asset.native).filename.to_s
        )
      end
    end
  end
end
