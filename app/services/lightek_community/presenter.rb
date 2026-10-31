# frozen_string_literal: true
module LightekCommunity
  class Presenter
    def initialize(access)
      @access = access
    end

    def profile(record)
      return nil unless record
      { id: record.id, name: record.public_display_name, display_handle: record.display_handle,
        avatar_url: record.avatar_url, bio: record.bio, profile_type: record.profile_type }
    end

    def community(record)
      { id: record.id, slug: record.slug, name: record.name, description: record.description,
        cover_url: record.cover.attached? ? "/api/lightek/pwa/communities/#{record.slug}/cover" : nil,
        audience: record.audience, visibility: record.visibility, sections: record.sections, owner: profile(record.owner_profile),
        member_count: record.memberships.count, joined: !!record.member?(@access.profile),
        can_manage: !!(@access.super_admin? || record.manager?(@access.profile)) }
    end

    def post(record)
      engagements = @access.profile ? record.engagements.where(profile_id: @access.profile.id).pluck(:kind) : []
      { id: record.id, title: record.title, content: record.content, kind: record.kind,
        audience: record.audience, visibility: record.visibility, parent_id: record.parent_id, author: profile(record.user.profile),
        community: record.community && { slug: record.community.slug, name: record.community.name },
        live_status: record.kind=="live" ? StudioLiveOperation.find_by(id:record.metadata["live_operation_id"])&.status : nil,
        live_url: record.kind=="live" ? "/api/lightek/pwa/live/#{record.id}/index.m3u8" : nil,
        metadata: record.metadata, created_at: record.created_at.iso8601, expires_at: record.expires_at&.iso8601,
        can_edit: !!(@access.super_admin? || record.user_id == @access.user&.id),
        can_delete: !!(@access.super_admin? || record.user_id == @access.user&.id || record.community&.manager?(@access.profile)),
        reply_count: @access.posts.where(parent_id: record.id).count,
        like_count: record.engagements.where(kind: "like").count,
        rsvp_count: record.engagements.where(kind: "rsvp").count,
        engagements: engagements,
        media: record.media.map { |file| { url: "/api/lightek/pwa/posts/#{record.id}/media/#{file.id}",
          content_type: file.blob.content_type, filename: file.blob.filename.to_s } } }
    end
  end
end
