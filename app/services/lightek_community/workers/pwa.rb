# frozen_string_literal: true
module LightekCommunity
  module Workers
    class Pwa
      ACTIONS = %w[community_create community_update community_join community_leave community_member
        post_create post_update post_delete engage community_chat watch_party profile_preferences top_people_save].freeze
      def self.perform(action, payload = {}) = new(action, payload).perform
      def initialize(action, payload)
        @action = action.to_s
        @payload = payload.to_h.deep_stringify_keys
        @user = User.find(@payload.fetch("user_id"))
        @access = Access.new(user: @user, site_id: @payload["site_id"])
        @profile = @access.require_profile!
        @presenter = Presenter.new(@access)
      end

      def perform
        LightekPwa::Policy.new(user: @user, site: DymondSite::Site.find(@access.site_id)).authorize_capability!("community." + @action.delete_prefix("community_").tr("_", ".")) if @access.site_id
        raise ArgumentError, "Unsupported community action" unless ACTIONS.include?(@action)
        public_send(@action)
      end

      def community_create
        record = nil
        @user.with_lock do
          key = @payload.fetch("request_key").to_s
          raise ArgumentError, "Request key required" unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
          existing = Community.find_by(owner_profile: @profile, request_key: key, site_id: @access.site_id)
          return { community: @presenter.community(@access.community!(existing.slug)) } if existing
          audience = @payload.fetch("audience", "everyone")
          Audience.authorize!(audience, profile: @profile, super_admin: @access.super_admin?)
          record = Community.create!(audience: audience, request_key: key, owner_profile: @profile, site_id: @access.site_id,
            name: @payload.fetch("name"), description: @payload["description"],
            slug: "#{@payload.fetch('name').to_s.parameterize.first(130).presence || 'community'}-#{SecureRandom.hex(4)}",
            visibility: @payload.fetch("visibility", "public"))
          record.memberships.create!(profile: @profile, role: "owner")
        end
        { community: @presenter.community(record) }
      end

      def community_update
        record = community
        @access.manage!(record)
        if @payload["cover_id"].present?
          blob = ActiveStorage::Blob.find_signed!(@payload["cover_id"])
          raise AccessDenied, "Upload belongs to another account" unless blob.metadata["lightek_user_id"] == @user.id && blob.metadata["lightek_site_id"] == @access.site_id
          record.cover = blob
        end
        Audience.authorize!(@payload.fetch("audience", record.audience), profile: @profile, super_admin: @access.super_admin?)
        record.update!(@payload.slice("name", "description", "visibility", "sections", "audience"))
        { community: @presenter.community(record) }
      end

      def community_join
        record = community
        record.with_lock do
          record.memberships.find_or_create_by!(profile: @profile)
        end
        { community: @presenter.community(record) }
      end

      def community_leave
        record = community
        raise AccessDenied, "The community owner cannot leave their community" if record.owner_profile_id == @profile.id
        record.memberships.where(profile: @profile).destroy_all
        { community: @presenter.community(record) }
      end

      def community_member
        record = community
        @access.manage!(record)
        target = Profile.where.not(id: @access.blocked_profile_ids).find(@payload.fetch("profile_id"))
        Audience.authorize!(record.audience, profile: target, super_admin: target.user.role == "super_admin") unless @payload["role"] == "remove"
        membership = record.memberships.find_or_initialize_by(profile: target)
        raise AccessDenied, "The community owner cannot be removed or demoted" if membership.profile_id == record.owner_profile_id
        case @payload.fetch("role")
        when "remove" then membership.destroy!
        when "member", "admin" then membership.update!(role: @payload["role"])
        else raise ArgumentError, "Invalid member role"
        end
        { community: @presenter.community(record) }
      end

      def post_create
        # Serialized per author so job retries cannot duplicate an upload/post.
        @user.with_lock do
          request_key = @payload.fetch("request_key").to_s
          raise ArgumentError, "A request key is required" unless request_key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)
          existing = Post.find_by(user_id: @user.id, request_key: request_key, site_id: @access.site_id)
          return { post: @presenter.post(@access.posts.find(existing.id)) } if existing
          parent = @payload["parent_id"].present? ? @access.posts.find(@payload["parent_id"]) : nil
          raise ArgumentError, "Reply to the original post" if parent&.parent_id
          record_community = parent&.community || (@payload["slug"].present? ? community : nil)
          @access.participate!(record_community) if record_community
          visibility = parent&.visibility || @payload.fetch("visibility", "public")
          raise ArgumentError, "Community visibility requires a community" if visibility == "community" && !record_community
          audience = parent&.audience || @payload.fetch("audience", "everyone")
          Audience.compatible!(record_community, audience)
          Audience.authorize!(audience, profile: @profile, super_admin: @access.super_admin?)
          kind = parent ? "post" : @payload.fetch("kind", "post")
          raise ArgumentError,"Start live broadcasts through Live Studio" if kind=="live"
          metadata = @payload.fetch("metadata", {}).slice("starts_at", "location", "item_ids")
          if kind == "event"
            raise ArgumentError, "Event start time is required" if metadata["starts_at"].blank?
            metadata["starts_at"] = Time.iso8601(metadata["starts_at"]).iso8601
          end
          if %w[playlist series].include?(kind)
            ids = Array(metadata["item_ids"]).map { |id| Integer(id) }.uniq.first(100)
            raise AccessDenied, "Collection contains unavailable media" unless @access.posts.where(id: ids, kind: %w[video clip photo audio]).count == ids.length
            metadata["item_ids"] = ids
          end
          record = Post.new(user: @user, site_id: @access.site_id, community: record_community,
            parent: parent, title: @payload["title"], content: @payload["content"], kind: kind,
            audience: audience, visibility: visibility, metadata: metadata, request_key: request_key,
            expires_at: kind == "story" ? 24.hours.from_now : nil)
          blobs = Array(@payload["media_ids"]).map do |id|
            blob = ActiveStorage::Blob.find_signed!(id)
            raise AccessDenied, "Upload belongs to another account" unless blob.metadata["lightek_user_id"] == @user.id && blob.metadata["lightek_site_id"] == @access.site_id
            raise AccessDenied, "Upload is already attached" if blob.attachments.exists?
            blob
          end
          record.media.attach(blobs) if blobs.any?
          record.save!
          { post: @presenter.post(record) }
        end
      end

      def post_update
        record = @access.posts.find(@payload.fetch("post_id"))
        raise AccessDenied, "Only the author can edit this post" unless @access.super_admin? || record.user_id == @user.id
        audience = @payload.fetch("audience", record.audience)
        if record.parent_id
          raise ArgumentError, "Replies inherit the conversation audience" if audience != record.audience
        end
        Audience.compatible!(record.community, audience)
        Audience.authorize!(audience, profile: @profile, super_admin: @access.super_admin?)
        record.update!(@payload.slice("title", "content", "audience"))
        { post: @presenter.post(record) }
      end

      def post_delete
        record = @access.posts.find(@payload.fetch("post_id"))
        raise AccessDenied, "Only the author or a community administrator can delete this post" unless @access.super_admin? || record.user_id == @user.id || record.community&.manager?(@profile)
        record.destroy!
        { deleted_id: record.id }
      end

      def engage
        record = @access.posts.find(@payload.fetch("post_id"))
        @access.participate!(record.community) if record.community
        kind = @payload.fetch("kind")
        raise ArgumentError, "Unknown engagement" unless %w[like save rsvp].include?(kind)
        raise ArgumentError, "RSVP requires an event" if kind == "rsvp" && record.kind != "event"
        record.with_lock do
          scope = record.engagements.where(profile: @profile, kind: kind)
          if ActiveModel::Type::Boolean.new.cast(@payload.fetch("active"))
            scope.first_or_create!
          else
            scope.destroy_all
          end
        end
        { post: @presenter.post(record) }
      end

      def community_chat
        record = community
        @access.participate!(record)
        record.with_lock do
          conversation = context_conversation("community", record.id, record.name, record.owner_profile)
          { conversation_id: conversation.id }
        end
      end

      def watch_party
        record = @access.posts.find(@payload.fetch("post_id"))
        raise ArgumentError, "Watch parties require a video or clip" unless %w[video clip].include?(record.kind)
        @access.participate!(record.community) if record.community
        record.with_lock do
          conversation = context_conversation("watch_party", record.id, record.title.presence || "Watch party", record.user.profile)
          { conversation_id: conversation.id }
        end
      end

      def profile_preferences
        gender = @payload.fetch("community_gender")
        raise ArgumentError, "Choose a supported profile setting" unless Audience::GENDERS.include?(gender)
        @profile.update!(community_gender: gender)
        { community_gender: gender }
      end

      def top_people_save
        limit = Integer(@payload.fetch("limit"))
        raise ArgumentError, "Choose Top 5 or Top 8" unless [5, 8].include?(limit)
        ids = Array(@payload.fetch("profile_ids")).map { |id| Integer(id) }
        raise ArgumentError, "Choose distinct people within your selected limit" unless ids.uniq == ids && ids.length <= limit && !ids.include?(@profile.id)
        available = Profile.where(id: ids).where.not(id: @access.blocked_profile_ids)
        raise AccessDenied, "One of those people is unavailable" unless available.count == ids.length
        @profile.with_lock do
          @profile.top_people.destroy_all
          @profile.update!(top_people_limit: limit)
          ids.each_with_index { |id, i| @profile.top_people.create!(person_id: id, position: i + 1) }
        end
        { limit: limit, profile_ids: ids }
      end

      private

      def context_conversation(kind, id, title, owner)
        metadata = { "lightek_context" => true, "site_id" => @access.site_id,
          (kind == "community" ? "community_id" : "post_id") => id }
        conversation = LightekMessaging::Conversation.find_or_create_by!(kind: kind, metadata: metadata) do |record|
          record.title = title.to_s.first(120)
          record.created_by_profile = owner
        end
        member = conversation.participants.find_or_initialize_by(profile: @profile)
        member.assign_attributes(role: owner.id == @profile.id ? "owner" : "member", joined_at: member.joined_at || Time.current, left_at: nil)
        member.save!
        conversation
      end

      def community = @access.community!(@payload.fetch("slug"))
    end
  end
end
