# frozen_string_literal: true
module Api
  class LightekPwaController < ApplicationController
    allow_unauthenticated_access only: %i[show media cover live_playlist live_segment ott_catalog manifest spatial_manifest spatial_asset]
    before_action :resolve_context
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "Content not found" }, status: :not_found
    end
    protect_from_forgery with: :exception
    before_action { response.set_header("Cache-Control", "private, no-store") }

    rescue_from LightekPwa::Policy::Denied do |error|
      render json: {error: error.message}, status: :forbidden
    end

    def manifest
      render json: LightekPwa::Configuration.new(@site).manifest, content_type: "application/manifest+json"
    end

    def show
      render json: LightekCommunity::ReadModel.new(user: current_user, site_id: @site.id)
        .call(params.fetch(:view, "feed"), params.permit(:slug, :id, :before, :query).to_h)
    rescue LightekCommunity::AccessDenied => error
      render json: { error: error.message }, status: :forbidden
    rescue ArgumentError, KeyError => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    def media
      access = LightekCommunity::Access.new(user: current_user, site_id: @site.id)
      post = access.posts.find(params[:post_id])
      stream_blob(post.media.find(params[:attachment_id]).blob)
    end

    def cover
      access = LightekCommunity::Access.new(user: current_user, site_id: @site.id)
      community = access.community!(params[:slug])
      raise ActiveRecord::RecordNotFound unless community.cover.attached?
      stream_blob(community.cover.blob)
    end

    def ott_catalog
      access=LightekCommunity::Access.new(user:current_user,site_id:@site.id)
      records=access.posts.where(parent_id:nil,distribution:%w[lightek_streaming octavia]).where(kind:%w[video live]).order(id: :desc).limit(100)
      presenter=LightekCommunity::Presenter.new(access)
      render json:{schema_version:"1.0",items:records.map{|post|presenter.post(post)}}
    end

    def live_playlist
      post,operation=live_context
      path=::Studio::Live::Encoder.hls_path(operation.id)
      raise ActiveRecord::RecordNotFound unless path.file?
      content=path.read.lines.map do |line|
        value=line.strip
        if value.empty? || value.start_with?("#")
          line
        elsif value.match?(/\Asegment-\d+\.ts\z/)
          "/api/lightek/pwa/live/#{post.id}/segments/#{value}\n"
        else
          raise ActiveRecord::RecordNotFound
        end
      end.join
      render plain:content,content_type:"application/vnd.apple.mpegurl"
    end

    def live_segment
      _post,operation=live_context
      name=params[:name].to_s
      raise ActiveRecord::RecordNotFound unless name.match?(/\Asegment-\d+\.ts\z/)
      path=::Studio::Live::Encoder.hls_directory(operation.id).join(name)
      raise ActiveRecord::RecordNotFound unless path.file?
      send_file path,type:"video/mp2t",disposition:"inline"
    end

    def asset_file
      access = ::Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
      asset = StudioAsset.for_actor(access).find(params[:id])
      attachment = case params[:flavor]
      when "original" then asset.file
      when "native" then asset.native
      when "bundle" then asset.bundle
      when "proxy" then asset.proxy
      when "thumbnail" then asset.thumbnail
      else raise ActiveRecord::RecordNotFound
      end
      raise ActiveRecord::RecordNotFound unless attachment.attached?
      stream_blob(attachment.blob)
    end

    def spatial_manifest
      post=::LightekCommunity::Access.new(user:current_user,site_id:@site.id).posts.find(params[:post_id])
      render json: ::Studio::Spatial::Publication.manifest(post)
    end
    def spatial_asset
      post=::LightekCommunity::Access.new(user:current_user,site_id:@site.id).posts.find(params[:post_id])
      ref=Array(post.metadata.dig("spatial","assets")).find { |asset| asset["id"].to_s==params[:asset_id].to_s } or raise ActiveRecord::RecordNotFound
      stream_blob(post.spatial_files.blobs.find(ref.fetch("proxy_blob_id")))
    end
    def spatial_fork
      community=::LightekCommunity::Access.new(user:current_user,site_id:@site.id)
      post=community.posts.find(params[:post_id]);community.require_profile!
      access=::Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
      render json: ::Studio::Spatial::Publication.fork!(post,access:access,request_key:params.require(:request_key))
    rescue ArgumentError => error
      render json:{error:error.message},status: :unprocessable_entity
    end

    def spatial_hub
      access=::LightekCommunity::Access.new(user:current_user,site_id:@site.id)
      community=access.community!(params.require(:slug))
      posts=access.posts.where(community_id:community.id).order(id: :desc).limit(40)
      assets=posts.flat_map do |post|
        next [] unless post.metadata.dig("spatial","allow_remix")
        Array(post.metadata.dig("spatial","assets")).map { |ref| {post_id:post.id,asset_id:ref["id"],name:ref["name"],license:post.metadata.dig("spatial","license"),author:post.user.profile.public_display_name,url:"/api/lightek/pwa/posts/#{post.id}/spatial/assets/#{ref['id']}"} }
      end
      render json:{community:community.slug,assets:assets}
    end
    def spatial_hub_import
      community=::LightekCommunity::Access.new(user:current_user,site_id:@site.id)
      post=community.posts.find(params.require(:post_id));community.require_profile!
      access=::Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
      asset=::Studio::Spatial::Publication.import_asset!(post,access:access,asset_id:params.require(:asset_id),request_key:params.require(:request_key))
      render json:{asset_id:asset.id,name:asset.name,status:asset.status}
    rescue ArgumentError => error
      render json:{error:error.message},status: :unprocessable_entity
    end

    def spatial_generation
      access=::Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
      asset=case params.fetch(:operation,"create")
      when "create" then ::Studio::Spatial::Generation.submit(access:access,scene_id:params.require(:scene_id),prompt:params.require(:prompt),request_key:params.require(:request_key))
      when "status" then StudioAsset.for_actor(access).find(params.require(:asset_id))
      when "retry" then ::Studio::Spatial::Generation.retry!(access,StudioAsset.for_actor(access).find(params.require(:asset_id)))
      else raise ArgumentError,"Unsupported generation operation"
      end
      render json: ::Studio::Spatial::Generation.status(asset)
    rescue ArgumentError => error
      render json:{error:error.message},status: :unprocessable_entity
    end

    def spatial_session
      access=::Studio::PwaAccess.new("user_id"=>current_user.id,"site_id"=>@site.id)
      client=::Studio::Spatial::Client.new(access,origin:request.base_url)
      result=case params.fetch(:operation,"create")
      when "create" then client.create(access.scene!(params.require(:scene_id)))
      when "ticket" then client.ticket(params.require(:session_id))
      when "close" then client.close(params.require(:session_id))
      else raise ArgumentError,"Unsupported Blender session operation"
      end
      result["ws_url"]="#{request.ssl? ? 'wss' : 'ws'}://#{request.host_with_port}/studio-spatial/ws" unless result["closed"]
      render json:result
    rescue ArgumentError => error
      render json:{error:error.message},status: :unprocessable_entity
    end

    def upload
      file = params.require(:file)
      raise ArgumentError, "Choose a media file" unless file.respond_to?(:tempfile)
      raise ArgumentError, "File must be smaller than 250 MB" if file.size > 250.megabytes
      studio_kind = nil
      if params[:purpose]=="studio_asset" && %w[.blend .glb].include?(File.extname(file.original_filename).downcase)
        magic=File.binread(file.tempfile.path,12)
        studio_kind = "blend" if magic.start_with?("BLENDER")
        studio_kind = "glb" if magic.start_with?("glTF")
        raise ArgumentError,"File does not match its asset format" unless studio_kind
      end
      type = Marcel::MimeType.for(file.tempfile, name: file.original_filename, declared_type: file.content_type)
      allowed = Post::MEDIA_TYPES
      type = studio_kind=="blend" ? "application/x-blender" : "model/gltf-binary" if studio_kind
      raise ArgumentError, "Unsupported media type" unless studio_kind || allowed.include?(type)
      blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename,
        content_type: type, identify: false,
        metadata: { "lightek_user_id" => current_user.id, "lightek_site_id" => @site.id, "studio_kind" => studio_kind })
      render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, content_type: type }, status: :created
    rescue ArgumentError => error
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def live_context
      access=LightekCommunity::Access.new(user:current_user,site_id:@site.id)
      post=access.posts.where(kind:"live").find(params[:post_id])
      operation=StudioLiveOperation.find(post.metadata["live_operation_id"])
      raise ActiveRecord::RecordNotFound unless operation.metadata["owner_id"].to_s==post.user_id.to_s && operation.metadata["post_id"].to_s==post.id.to_s
      [post,operation]
    end

    def stream_blob(blob)
      size = blob.byte_size
      self.content_type = blob.content_type
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["Content-Disposition"] = "inline"
      range = request.headers["Range"]
      if range.present?
        match = range.match(/\Abytes=(\d*)-(\d*)\z/)
        if match && (match[1].present? || match[2].present?)
          first = match[1].present? ? match[1].to_i : [size - match[2].to_i, 0].max
          last = match[1].blank? || match[2].blank? ? size - 1 : [match[2].to_i, size - 1].min
          if first <= last && first < size
            response.status = 206
            response.headers["Content-Range"] = "bytes #{first}-#{last}/#{size}"
            response.headers["Content-Length"] = (last - first + 1).to_s
            self.response_body = request.head? ? [] : Enumerator.new { |out| (first..last).step(1.megabyte) { |offset| out << blob.download_chunk(offset..[offset + 1.megabyte - 1, last].min) } }
            return
          end
        end
        response.headers["Content-Range"] = "bytes */#{size}"
        head :range_not_satisfiable
        return
      end
      response.headers["Content-Length"] = size.to_s
      self.response_body = request.head? ? [] : Enumerator.new { |out| blob.download { |chunk| out << chunk } }
    end

    def require_authentication
      return if authenticated?
      render json: { error: "Authentication required" }, status: :unauthorized
    end

    def resolve_context
      authenticated?
      @site = LightekPwa::SiteContext.resolve(request.host)
      surface = case action_name
      when "manifest" then nil
      when "asset_file", "spatial_session", "spatial_generation", "spatial_fork", "spatial_hub", "spatial_hub_import" then "studio"
      when "upload" then params[:purpose] == "studio_asset" ? "studio" : "create"
      when "spatial_manifest", "spatial_asset" then "home"
      when "ott_catalog", "live_playlist", "live_segment" then "watch"
      when "show" then {"feed" => "home", "saved" => "home", "profile" => "space", "community" => "communities", "post" => "home", "media" => "watch"}.fetch(params.fetch(:view, "feed"), params[:view])
      end
      LightekPwa::Policy.new(user: current_user, site: @site).authorize!(surface) unless action_name == "manifest"
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Lightek site not found" }, status: :not_found
    end
  end
end
