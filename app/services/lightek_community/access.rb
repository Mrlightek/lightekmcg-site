# frozen_string_literal: true
module LightekCommunity
  # One visibility policy is shared by feeds, permalink reads and mutations.
  class Access
    attr_reader :user, :profile, :site_id
    def initialize(user: nil, site_id: nil)
      @user = user
      @profile = user&.profile
      @site_id = site_id
    end

    def super_admin? = user&.role.to_s == "super_admin"

    def blocked_profile_ids
      return [] if !profile || super_admin?
      LightekSocial::Block.where(blocker_profile_id: profile.id).pluck(:blocked_profile_id) |
        LightekSocial::Block.where(blocked_profile_id: profile.id).pluck(:blocker_profile_id)
    end

    def communities
      base = Community.where(site_id: site_id).where.not(slug: nil).where.not(owner_profile_id: blocked_profile_ids)
      base = base.where(moderation_state: "active") unless super_admin?
      base = Audience.visible(base, profile: profile, super_admin: super_admin?)
      return base if super_admin?
      allowed = base.where(visibility: "public")
      return allowed unless profile
      allowed.or(base.where(owner_profile_id: profile.id))
        .or(base.where(id: Membership.where(profile_id: profile.id).select(:community_id)))
    end

    def community!(id) = communities.find_by!(slug: id.to_s)

    def posts
      base = Post.unexpired.where(site_id: site_id)
      base = base.where(moderation_state: "published") unless super_admin?
      blocked_users = Profile.where(id: blocked_profile_ids).select(:user_id)
      base = base.where.not(user_id: blocked_users)
      base = Audience.visible(base, profile: profile, super_admin: super_admin?)
      return base if super_admin?
      # A private community stays private even when its author chose Public.
      accessible = communities.select(:id)
      base = base.where(community_id: nil).or(base.where(community_id: accessible))
      base = base.where(parent_id: nil)
      visible = base.where(visibility: "public")
      unless profile
        return visible.or(Audience.visible(Post.unexpired.where(site_id: site_id, moderation_state: "published", parent_id: visible.select(:id)).where.not(user_id: blocked_users), profile: profile))
      end
      following = LightekSocial::Follow.where(follower_profile_id: profile.id).select(:followed_profile_id)
      following_users = Profile.where(id: following).select(:user_id)
      member_communities = Membership.where(profile_id: profile.id).select(:community_id)
      visible = visible.or(base.where(user_id: user.id))
        .or(base.where(visibility: "followers", user_id: following_users))
        .or(base.where(visibility: "community", community_id: member_communities))
      visible.or(Audience.visible(Post.unexpired.where(site_id: site_id, moderation_state: "published", parent_id: visible.select(:id)).where.not(user_id: blocked_users), profile: profile))
    end

    def require_profile!
      raise AccessDenied, "A Lightek profile is required" unless profile
      profile
    end

    def manage!(community)
      require_profile!
      Audience.authorize!(community.audience, profile: profile, super_admin: super_admin?)
      raise AccessDenied, "Community administration requires an owner or administrator" unless super_admin? || community.manager?(profile)
    end

    def participate!(community)
      require_profile!
      Audience.authorize!(community.audience, profile: profile, super_admin: super_admin?)
      raise AccessDenied, "Join this community to participate" unless super_admin? || community.member?(profile)
    end
  end
end
