# frozen_string_literal: true

module Api
  module Studio
    class PipelineController < ApplicationController
      TOKEN_PURPOSE = "studio-pipeline-watcher"
      TOKEN_DURATION = 24.hours
      skip_before_action :require_authentication, only: :ingest
      protect_from_forgery with: :exception
      skip_forgery_protection only: :ingest, if: :bearer_ingest?
      before_action :authenticate_ingest, only: :ingest
      before_action :pipeline_context
      before_action { response.set_header("Cache-Control", "private, no-store") }

      rescue_from ActiveRecord::RecordNotFound do
        render json: {error: "Studio workspace or asset not found"}, status: :not_found
      end
      rescue_from LightekPwa::Policy::Denied do |error|
        render json: {error: error.message}, status: :forbidden
      end
      rescue_from ArgumentError, KeyError, TypeError, ActiveRecord::RecordInvalid do |error|
        render json: {error: error.message.to_s.first(500)}, status: :unprocessable_entity
      end

      def page
        credentials = ::Studio::Pipeline::MixamoCredentials
        @mixamo_operator = credentials.operator?(current_user)
        if @mixamo_operator
          @mixamo_configured = credentials.configured?
          @mixamo_waiting_count = StudioOperation.where(capability: ::Studio::Pipeline::CharacterAnimation::CAPABILITY,
            status: "awaiting_manual_login", studio_project_id: StudioProject.where(site: @site)).count
        end
        @character_jobs = ::Studio::Pipeline::CharacterAnimation.new(@access).operations.order(id: :desc).limit(10)
        render "studio_pipeline/index", layout: false
      end

      def index
        cards = @access.cards.with_attached_proxy.with_attached_pipeline_base.order(updated_at: :desc).limit(150)
        query = params[:q].to_s.strip.first(120)
        items = @access.assets.where(kind: %w[glb blend], status: "ready")
          .joins(:proxy_attachment).with_attached_proxy.order(updated_at: :desc)
        if query.present?
          items = items.where("studio_assets.name ILIKE ?", "%#{StudioAsset.sanitize_sql_like(query)}%")
        end
        render json: {
          cards: cards.map { |asset| card_json(asset) },
          readyAssets: items.limit(150).map { |asset| card_json(asset) },
          renders: @access.renders.order(id: :desc).limit(30).map { |operation| render_json(operation) }
        }
      end

      def ingest
        asset = ::Studio::Pipeline::Intake.new(@access, file: params.require(:file),
          sidecars: Array(params[:sidecars]), sidecar_paths: Array(params[:sidecar_paths]),
          mode: params.fetch(:mode, "props"), target: params[:asset_id], model_path: params[:model_path]).call
        render json: card_json(asset.reload), status: :accepted
      end

      def mixamo
        asset = @access.cards.find(params[:id])
        asset.with_lock do
          raise ArgumentError, "Wait for the base mesh to finish preparing" unless
            asset.metadata["pipeline_stage"].in?(%w[base mixamo]) && asset.pipeline_base.attached?
          asset.update!(metadata: asset.metadata.merge("pipeline_stage" => "mixamo"))
        end
        render json: card_json(asset).merge(downloadUrl: studio_pipeline_asset_path(asset, "mixamo", site_id: @site.id))
      end

      def asset
        case params[:flavor]
        when "mixamo"
          record = @access.cards.find(params[:id])
          attachment = record.pipeline_base
          disposition = "attachment"
        when "glb"
          record = @access.assets.where(status: "ready", kind: %w[glb blend]).find(params[:id])
          attachment = record.proxy
          disposition = "inline"
        else
          raise ActiveRecord::RecordNotFound
        end
        raise ActiveRecord::RecordNotFound unless attachment.attached?
        redirect_to rails_storage_proxy_path(attachment.blob, disposition: disposition)
      end

      def watcher_token
        if Current.session.connect_delegation.present?
          raise LightekPwa::Policy::Denied, "Use your own Studio session to issue a watcher token"
        end
        expires = TOKEN_DURATION.from_now
        token = verifier.generate({"session_id" => Current.session.id, "site_id" => @site.id},
          purpose: TOKEN_PURPOSE, expires_at: expires)
        scope = verifier.generate({"user_id" => current_user.id, "site_id" => @site.id}, purpose: "studio-pipeline-scope")
        render json: {token: token, expiresAt: expires.iso8601, scope: Digest::SHA256.hexdigest(scope),
          ingestUrl: "#{request.base_url}/api/v1/assets/ingest"}
      end

      def render_video
        operation = ::Studio::Pipeline::Render.new(@access, request.request_parameters).submit
        render json: render_json(operation), status: :accepted
      end

      def video
        operation = @access.renders.where(status: "completed").find(params[:id])
        attachment = operation.artifacts.find_by!(kind: "video").file
        raise ActiveRecord::RecordNotFound unless attachment.attached?
        redirect_to rails_storage_proxy_path(attachment.blob, disposition: params[:download] == "1" ? "attachment" : "inline")
      end

      private

      def verifier = Rails.application.message_verifier("studio-pipeline-watcher")
      def bearer_ingest? = action_name == "ingest" && request.authorization.present?

      def authenticate_ingest
        return require_authentication unless bearer_ingest?
        token = request.authorization.to_s[/\ABearer ([^\s]{1,4096})\z/i, 1]
        proof = token && verifier.verified(token, purpose: TOKEN_PURPOSE)
        return render json: {error: "Watcher token is invalid or expired"}, status: :unauthorized unless proof.is_a?(Hash)
        watcher_session = Session.find_by(id: proof["session_id"])
        if watcher_session.nil? || watcher_session.connect_delegation.present? || watcher_session.mfa_enrollment_only?
          return render json: {error: "Watcher session has ended"}, status: :unauthorized
        end
        if watcher_session.identity_connection_id
          connection = LightekIdentity::Connection.find_by(id: watcher_session.identity_connection_id, enabled: true)
          return render json: {error: "Watcher login is no longer active"}, status: :unauthorized unless connection
          LightekIdentity::Oidc.active_member!(connection, watcher_session.user)
        end
        @watcher_site = proof.fetch("site_id")
        @watcher_user = watcher_session.user
        if params[:asset_id].present? || params[:mode].present? && params[:mode] != "props"
          return render json: {error: "Watcher tokens can create new ingest cards only"}, status: :forbidden
        end
      rescue LightekIdentity::Oidc::Invalid
        render json: {error: "Watcher login is no longer active"}, status: :unauthorized
      end

      def pipeline_context
        actor = @watcher_user || current_user
        @site = ::Studio::Broadcasting::Access.site(user: actor, host: request.host, id: @watcher_site || params[:site_id])
        if action_name == "page" && @site.nil?
          @sites = LightekPwa::Policy.sites_for(actor).order(:name)
          render "studio_pipeline/choose_site", layout: false
          return
        end
        raise ActiveRecord::RecordNotFound unless @site
        @access = ::Studio::Pipeline::Access.new(actor, @site)
      end

      def card_json(asset)
        metadata = asset.metadata
        stage = metadata["pipeline_stage"] || "ready"
        stage = "rendered" if stage == "ready" && metadata["pipeline_rendered_at"].present?
        status = asset.status
        status = metadata["pipeline_prepared"] ? "prepared" : "queued" if status == "uploaded"
        {
          id: asset.id, name: asset.name, stage: stage, status: status, error: asset.error_message,
          clips: ::Studio::Pipeline::Render.clips(asset), modelPath: metadata["pipeline_model_path"],
          previewUrl: (studio_pipeline_asset_path(asset, "glb", site_id: @site.id, version: asset.proxy.blob.id) if asset.proxy.attached? && asset.status == "ready"),
          canPrepare: asset.pipeline_base.attached? && stage.in?(%w[base mixamo]),
          sourceName: metadata["pipeline_source_name"]
        }
      end

      def render_json(operation)
        {
          id: operation.id, status: operation.status, error: operation.error_message,
          createdAt: operation.created_at.iso8601,
          videoUrl: (studio_pipeline_video_path(operation, site_id: @site.id) if operation.status == "completed"),
          downloadUrl: (studio_pipeline_video_path(operation, site_id: @site.id, download: 1) if operation.status == "completed")
        }
      end
    end
  end
end
