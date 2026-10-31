# frozen_string_literal: true
module LightekCommunity
  class ReadModel
    def initialize(user: nil, site_id: nil)
      @access = Access.new(user: user, site_id: site_id)
      @presenter = Presenter.new(@access)
    end

    def call(view, params = {})
      case view.to_s
      when "money"
        LightekPwa::Money.call(@access.user)
      when "communities"
        records = @access.communities.order(:name, :id)
        records = search(records, %w[name description], params["query"])
        { communities: records.limit(50).map { |c| @presenter.community(c) } }
      when "community"
        community = @access.community!(params.fetch("slug"))
        records = @access.posts.where(community: community, parent_id: nil)
        { community: @presenter.community(community), **feed(records, params),
          members: community.memberships.includes(:profile).where.not(profile_id: @access.blocked_profile_ids).order(:id).limit(50).map { |m| @presenter.profile(m.profile).merge(role: m.role) } }
      when "post"
        post = @access.posts.find(params.fetch("id"))
        { post: @presenter.post(post), **feed(@access.posts.where(parent_id: post.id), params) }
      when "profile"
        profile = Profile.where.not(id: @access.blocked_profile_ids).find(params.fetch("id"))
        { profile: @presenter.profile(profile),
          profile_preferences: profile.id == @access.profile&.id ? { community_gender: profile.community_gender } : nil,
          top_people_limit: profile.top_people_limit,
          top_people: profile.top_people.includes(:person).where.not(person_id: @access.blocked_profile_ids | Access.new(user: profile.user, site_id: @access.site_id).blocked_profile_ids).map { |entry| @presenter.profile(entry.person).merge(position: entry.position) }, **feed(@access.posts.where(user_id: profile.user_id, parent_id: nil), params),
          communities: @access.communities.where(id: Membership.where(profile_id: profile.id).select(:community_id)).limit(50).map { |c| @presenter.community(c) } }
      when "feed", "watch", "clips", "explore", "saved", "media"
        records = @access.posts.where(parent_id: nil)
        records = records.where(kind: %w[video clip photo audio]) if view.to_s == "media"
        records = records.where(kind: %w[video live]) if view.to_s == "watch"
        records = records.where(kind: %w[clip story]) if view.to_s == "clips"
        if view.to_s == "saved"
          @access.require_profile!
          records = records.where(id: Engagement.where(profile_id: @access.profile.id, kind: "save").select(:post_id))
        end
        records = search(records, %w[title content], params["query"])
        result = feed(records, params)
        if %w[feed watch clips].include?(view.to_s)
          setting = LightekPwa::Application.find_by(site_id: @access.site_id)&.settings || {}
          surface_key = view.to_s == "feed" ? "home" : view.to_s
          pinned = setting.fetch("surfaces", {}).fetch(surface_key, {}).fetch("modules", {}).values.flat_map { |mod| Array(mod["post_ids"]) }.uniq.first(100)
          result[:featured_posts] = @access.posts.where(id: pinned, parent_id: nil).order(id: :desc).map { |post| @presenter.post(post) }
          result[:communities] = @access.communities.order(:name).limit(8).map { |community| @presenter.community(community) }
          result[:people] = Profile.where(id: LightekPwa::Membership.where(site_id: @access.site_id, status: "active").select(:profile_id)).where.not(id: @access.blocked_profile_ids).limit(12).map { |person| @presenter.profile(person) }
        end
        if view.to_s == "explore"
          people = Profile.where.not(id: @access.blocked_profile_ids)
          result[:people] = search(people, %w[display_name handle bio], params["query"]).limit(30).map { |p| @presenter.profile(p) }
          result[:communities] = search(@access.communities, %w[name description], params["query"]).limit(30).map { |c| @presenter.community(c) }
        end
        result
      else
        raise ArgumentError, "Unknown Lightek view"
      end
    end

    private

    def feed(records, params)
      records = records.where("posts.id < ?", Integer(params["before"])) if params["before"].present?
      rows = records.order(id: :desc).includes(:community, user: :profile, media_attachments: :blob).limit(31).to_a
      { posts: rows.first(30).map { |p| @presenter.post(p) }, next_before: rows.length > 30 ? rows[29].id : nil }
    end

    def search(records, columns, query)
      return records if query.blank?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.first(200))}%"
      records.where(columns.map { |c| "LOWER(#{c}) LIKE LOWER(:query)" }.join(" OR "), query: pattern)
    end
  end
end
