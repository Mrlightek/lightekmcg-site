# frozen_string_literal: true
module LightekCommunity
  class ConversationAccess
    def self.authorize!(conversation, profile, write: false)
      context = conversation.metadata.to_h
      return unless context["lightek_context"] == true
      policy = LightekPwa::Policy.new(user: profile.user, site: DymondSite::Site.find(context.fetch("site_id")))
      policy.authorize!("messages")
      raise LightekMessaging::AccessDenied, "This conversation is closed" if write && context["administratively_closed"] == true && !policy.super_admin?
      access = Access.new(user: profile.user, site_id: context.fetch("site_id"))
      if conversation.community?
        record = access.communities.find(context.fetch("community_id"))
        access.participate!(record)
      elsif conversation.watch_party?
        record = access.posts.find(context.fetch("post_id"))
        access.participate!(record.community) if record.community
      end
    rescue ActiveRecord::RecordNotFound, AccessDenied, LightekPwa::Policy::Denied, KeyError
      raise LightekMessaging::AccessDenied, "This community or watch party is unavailable"
    end

    def self.allowed?(conversation, profile)
      authorize!(conversation, profile)
      true
    rescue LightekMessaging::AccessDenied
      false
    end
  end
end
