# frozen_string_literal: true
module Studio
  module Publishers
    class LightekSocial < Base
      def call
        metadata = publication.metadata.to_h
        project = publication.studio_project
        user = User.find(metadata.fetch("user_id"))
        workspace = Studio::PwaAccess.new("user_id" => user.id, "site_id" => project.site_id)
        unless workspace.projects.exists?(id: project.id)
          raise ::LightekCommunity::AccessDenied, "Publication does not belong to this creator or application"
        end
        unless publication.artifact.studio_operation&.studio_project_id == project.id
          raise ::LightekCommunity::AccessDenied, "Artifact is outside this project"
        end
        raise ArgumentError, "Publication artifact is not attached" unless publication.artifact.file.attached?
        site_id = project.site_id || metadata["site_id"]
        ::LightekPwa::Policy.new(user: user, site: DymondSite::Site.find(site_id)).authorize!("create") if site_id
        access = ::LightekCommunity::Access.new(user: user, site_id: site_id)
        community = metadata["community_slug"].present? ? access.community!(metadata["community_slug"]) : nil
        access.participate!(community) if community
        ::LightekCommunity::Audience.authorize!(metadata.fetch("audience","everyone"),profile:user.profile,super_admin:access.super_admin?)
        ::LightekCommunity::Audience.compatible!(community,metadata.fetch("audience","everyone"))
        post = nil
        user.with_lock do
          key = "studio-publication-#{publication.id}"
          post = ::Post.find_by(user_id: user.id, request_key: key)
          unless post
            type = publication.artifact.file.blob.content_type
            kind = case type
            when /\Avideo\// then "video"
            when /\Aimage\// then "photo"
            when /\Aaudio\// then "post"
            else raise ArgumentError, "Only image, video or audio artifacts can be published"
            end
            post = ::Post.new(user: user, site_id: site_id, community: community,
              title: metadata["title"].presence || project.name, content: metadata["content"],
              kind: kind, distribution: publication.platform, audience: metadata.fetch("audience","everyone"), visibility: community&.visibility == "private" ? "community" : "public", request_key: key)
            post.media.attach(publication.artifact.file.blob)
            post.save!
          end
        end
        publication.update!(metadata: metadata.merge("post_id" => post.id))
        { "post_id" => post.id, "url" => "/lightek/index.html#/post/#{post.id}" }
      end
    end
  end
end
