# frozen_string_literal: true
module Studio
  module Live
    class Sessions
      class Busy < StandardError; end
      def self.scope = StudioLiveOperation.where("metadata ->> 'broadcaster' = ?", "browser_v1")
      def self.for_user(user)
        ::Gatekeeper::StudioLivePolicy.authorize!(user: user)
        scope.where("CAST(metadata ->> 'owner_id' AS TEXT) = ?", user.id.to_s)
      end
      def self.find!(id, user)
        operation = scope.find(id)
        ::Gatekeeper::StudioLivePolicy.authorize!(user: user, operation: operation)
        authorize_content!(operation,user)
        operation
      end
      def self.authorize_content!(operation,user)
        return unless operation.metadata["destination"]=="lightek"
        access=LightekCommunity::Access.new(user:user,site_id:operation.studio_project.site_id)
        post=access.posts.find(operation.metadata.fetch("post_id"))
        access.participate!(post.community) if post.community
      end
      def self.create!(user:, destination:, title:, site: nil, community_slug: nil, audience: "everyone")
        ::Gatekeeper::StudioLivePolicy.authorize!(user: user)
        raise ArgumentError, "Choose a supported destination." unless %w[test tiktok restream lightek].include?(destination)
        if !%w[test lightek].include?(destination) && !Destination.configured?(user, provider: destination)
          raise Destination::Unavailable, "Configure your #{Destination.provider!(destination)[:label]} streaming destination first."
        end
        raise Encoder::Failure, "FFmpeg is not installed on the application server." unless Encoder.available?
        raise ArgumentError,"A configured site is required for Lightek broadcasts." if destination=="lightek" && !site
        title = title.to_s.strip
        raise ArgumentError, "Enter a broadcast title of 1–120 characters." unless title.length.between?(1, 120)
        user.with_lock do
          # Serialize capacity reservations across Passenger processes on PostgreSQL.
          user.class.connection.execute("SELECT pg_advisory_xact_lock(54182931)") if user.class.connection.adapter_name == "PostgreSQL"
          scope.where(status: %w[draft connecting live]).where("updated_at < ?", 45.seconds.ago).update_all(status: "failed", error_message: "Capture connection expired.", ended_at: Time.current)
          raise Busy, "End your current broadcast session before starting another." if for_user(user).where(status: %w[draft connecting live]).exists?
          raise Busy, "The broadcaster is at capacity. Try again after another session ends." if scope.where(status: %w[draft connecting live]).count >= 2
          project = StudioProject.create!(owner: user, site: site, name: title, description: "Lightek browser broadcast")
          operation=StudioLiveOperation.create!(studio_project: project, platform: %w[test lightek].include?(destination) ? "lightek_streaming" : "tiktok", status: "draft", credential_ref: %w[test lightek].include?(destination) ? nil : Destination.slug(user, provider: destination),
            metadata: {"broadcaster" => "browser_v1", "owner_id" => user.id, "destination" => destination, "title" => title})
          if destination=="lightek"
            access=LightekCommunity::Access.new(user:user,site_id:site&.id)
            community=community_slug.present? ? access.community!(community_slug) : nil
            access.participate!(community) if community
            LightekCommunity::Audience.authorize!(audience,profile:user.profile,super_admin:access.super_admin?)
            LightekCommunity::Audience.compatible!(community,audience)
            post=Post.create!(user:user,site:site,community:community,kind:"live",distribution:"lightek_streaming",title:title,audience:audience,
              visibility:community&.visibility=="private" ? "community" : "public",request_key:"live-#{operation.id}",metadata:{"live_operation_id"=>operation.id})
            operation.update!(metadata:operation.metadata.merge("post_id"=>post.id))
          end
          operation
        end
      end
      def self.ticket(operation, user)
        Rails.application.message_verifier("studio_live").generate({"operation_id" => operation.id, "user_id" => user.id}, purpose: "browser_broadcast", expires_in: 2.minutes)
      end
      def self.from_ticket!(ticket, user)
        data = Rails.application.message_verifier("studio_live").verified(ticket.to_s, purpose: "browser_broadcast")
        raise ::Gatekeeper::StudioLivePolicy::Denied, "Broadcast connection expired. Start a new session." unless data && data["user_id"].to_s == user.id.to_s
        find!(data.fetch("operation_id"), user)
      end
      def self.event!(operation, event, error = nil)
        status = {"sending" => "live", "ended" => "ended", "failed" => "failed"}.fetch(event)
        attrs = {status: status, updated_at: Time.current}
        attrs[:started_at] = Time.current if status == "live"
        attrs.merge!(ended_at: Time.current, error_message: error) if %w[ended failed].include?(status)
        scope.where(id: operation.id, status: %w[connecting live ending]).update_all(attrs)
        Post.where(id:operation.metadata["post_id"],user_id:operation.metadata["owner_id"]).update_all(expires_at:24.hours.from_now) if %w[ended failed].include?(status)
      end
    end
  end
end
