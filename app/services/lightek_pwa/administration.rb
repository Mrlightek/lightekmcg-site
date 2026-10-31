# frozen_string_literal: true
module LightekPwa
  class Administration
    SECTIONS = %w[overview settings navigation content communities people studio live conversations audit integrations].freeze
    attr_reader :site, :user, :policy
    def initialize(site:, user:)
      @site, @user = site, user
      @policy = Policy.new(site: site, user: user)
      policy.authorize_admin!
    end
    def application = Application.find_or_initialize_by(site_id: site.id)
    def posts = Post.where(site_id: site.id)
    def communities = Community.where(site_id: site.id)
    def projects = StudioProject.where(site_id: site.id)
    def assets = StudioAsset.where(site_id: site.id)
    def live = StudioLiveOperation.where(studio_project_id: projects.select(:id))
    def conversations
      LightekMessaging::Conversation.where(kind: %w[community watch_party])
        .where("CAST(metadata ->> 'site_id' AS TEXT) = ?", site.id.to_s)
    end
    def people
      records = Profile.where(id: Membership.where(site_id: site.id).select(:profile_id))
        .or(Profile.where(id: LightekCommunity::Membership.where(community_id: communities.select(:id)).select(:profile_id)))
        .or(Profile.where(user_id: posts.select(:user_id)))
        .or(Profile.where(user_id: projects.select(:owner_id)))
      if defined?(LightekAgency::SiteMembership)
        records = records.or(Profile.where(user_id: LightekAgency::SiteMembership.where(site_id: site.id).select(:user_id)))
      end
      records = records.or(Profile.where(user_id: site.tenant.id)) if site.tenant.is_a?(User)
      records.includes(:user).order(:id)
    end
    def stats
      {"Posts" => posts.count, "Communities" => communities.count, "People" => people.count,
        "Productions" => projects.count, "Assets" => assets.count,
        "Live now" => live.where(status: %w[connecting live]).count,
        "Hidden posts" => posts.where(moderation_state: "hidden").count,
        "Failed jobs" => StudioOperation.where(studio_project_id: projects.select(:id), status: "failed").count}
    end
    def save!(raw)
      policy.authorize_admin!("settings")
      record = application
      permitted = raw.to_h.deep_stringify_keys.slice("name", "short_name", "description", "theme_color", "background_color", "status", "start_surface", "support_email", "welcome_message", "logo", "icon")
      settings = configuration_params(raw)
      site.with_lock do
        record = application
        record.lock_version = Integer(raw.fetch("lock_version")) if record.persisted?
        record.assign_attributes(permitted)
        %w[logo icon].each { |key| record.public_send("#{key}=", nil) if bool(raw["remove_#{key}"]) }
        record.updated_at = Time.current
        record.settings = record.settings.merge(settings)
        record.save!
        audit!("application.updated", record, fields: permitted.keys + settings.keys + %w[remove_logo remove_icon].select { |key| bool(raw[key]) })
      end
      record
    end
    def configuration_params(raw)
      raw = raw.to_h.deep_stringify_keys
      result = {}
      if raw["surfaces"]
        result["surfaces"] = raw["surfaces"].to_h.transform_values do |value|
          data = value.to_h.slice("label", "heading", "intro")
          data["enabled"] = bool(value["enabled"])
          data["position"] = Integer(value.fetch("position", 0))
          if value.key?("modules")
            data["modules"] = value["modules"].to_h.transform_values do |mod|
              raw_ids = mod.fetch("post_ids", "")
              ids = (raw_ids.is_a?(Array) ? raw_ids : raw_ids.to_s.split(/[\s,]+/)).reject(&:blank?).map { |id| Integer(id) }.uniq
              raise ArgumentError, "Choose at most fifty records per section" if ids.length > 50
              raise ArgumentError, "Section contains records from another application" unless posts.where(id: ids).count == ids.length
              {"label" => mod["label"].to_s, "position" => Integer(mod.fetch("position", 0)), "enabled" => bool(mod["enabled"]), "post_ids" => ids}
            end
          end
          data
        end
      end
      if raw["navigation"]
        result["navigation"] = raw["navigation"].to_h.reject { |key, value| key.start_with?("custom-") && value["label"].blank? }.transform_values do |value|
          value.to_h.slice("label", "surface_id", "href", "placement").merge("enabled" => bool(value["enabled"]), "position" => Integer(value.fetch("position", 0)))
        end
      end
      result
    rescue NoMethodError, TypeError
      raise ArgumentError, "Invalid application configuration"
    end
    def moderate!(kind, id, raw)
      record = nil
      ApplicationRecord.transaction do
        case kind
        when "post"
          record = posts.lock.find(id)
          record.update!(raw.slice("title", "content", "moderation_state", "visibility", "audience"))
        when "community"
          record = communities.lock.find(id)
          record.update!(raw.slice("name", "description", "moderation_state", "visibility", "audience", "sections"))
        when "delete_post"
          record = posts.lock.find(id)
          record.destroy!
        when "delete_community"
          raise Policy::Denied, "Community deletion requires an application administrator" unless policy.role == "admin"
          record = communities.lock.find(id)
          record.destroy!
        when "attachment"
          record = posts.lock.find(id)
          attachment = record.media.find(raw.fetch("attachment_id"))
          if record.media.size == 1 && record.title.blank? && record.content.blank?
            raise ArgumentError, "Add a title or text before removing this post's only attachment"
          end
          attachment.destroy!
        when "delete_asset"
          policy.authorize_admin!("studio")
          record = assets.lock.find(id)
          raise ArgumentError, "Wait for asset processing before deleting it" if %w[uploaded processing].include?(record.status)
          referenced = SceneObject.where(object_type: "imported_asset").where("CAST(definition ->> 'asset_id' AS TEXT) = ?", record.id.to_s).exists?
          timeline_use = StudioScene.select(:id, :settings).find_each.any? do |scene|
            timeline = scene.settings.is_a?(Hash) ? scene.settings["timeline"] : nil
            timeline.is_a?(Hash) && Array(timeline["clips"]).any? { |clip| clip.is_a?(Hash) && clip["asset_id"].to_i == record.id }
          end
          raise ArgumentError, "Remove this asset from scenes and timelines before deleting it" if referenced || timeline_use
          record.destroy!
        when "membership"
          policy.authorize_admin!("people")
          profile = people.find(id)
          protect_owner!(profile)
          record = Membership.find_or_initialize_by(site_id: site.id, profile_id: profile.id)
          record.update!(raw.slice("role", "status"))
        when "community_member"
          record = LightekCommunity::Membership.where(community_id: communities.select(:id)).find(id)
          raise Policy::Denied, "Community ownership cannot be removed here" if record.role == "owner"
          role = raw.fetch("role")
          raise ArgumentError, "Choose member, admin or remove" unless %w[member admin remove].include?(role)
          role == "remove" ? record.destroy! : record.update!(role: role)
        when "live"
          record = live.lock.find(id)
          raise ArgumentError, "Only an active broadcast can be ended" unless %w[draft connecting live ending].include?(record.status)
          record.update!(status: record.status == "draft" ? "cancelled" : "ending")
          posts.where(id: record.metadata["post_id"]).update_all(moderation_state: "hidden")
        when "asset"
          policy.authorize_admin!("studio")
          record = assets.lock.find(id)
          raise ArgumentError, "Only a failed import can be retried" unless record.status == "failed"
          record.update!(status: "uploaded", error_message: nil)
          StudioAssetIngestJob.perform_later(record.id)
        when "project"
          policy.authorize_admin!("studio")
          record = projects.lock.find(id)
          record.update!(raw.slice("name", "description"))
        when "operation"
          policy.authorize_admin!("studio")
          record = StudioOperation.where(studio_project_id: projects.select(:id)).lock.find(id)
          raise ArgumentError, "Only an active operation can be cancelled" unless %w[awaiting_planning awaiting_approval awaiting_payment pending running].include?(record.status)
          record.update!(status: "cancelled", completed_at: Time.current)
        when "publication"
          policy.authorize_admin!("studio")
          record = StudioPublication.where(studio_project_id: projects.select(:id)).lock.find(id)
          raise ArgumentError, "Only a queued publication can be cancelled" unless %w[draft scheduled].include?(record.status)
          record.update!(status: "cancelled")
        when "conversation"
          record = conversations.lock.find(id)
          record.update!(metadata: record.metadata.merge("administratively_closed" => bool(raw.fetch("closed"))))
        else
          raise ArgumentError, "Unsupported administration action"
        end
        audit!("#{kind}.updated", record, fields: raw.keys)
      end
      record
    end
    def add_community_member!(community_id:, email:, role:)
      raise ArgumentError, "Choose member or admin" unless %w[member admin].include?(role)
      community = communities.find(community_id)
      profile = User.find_by!(email_address: email.to_s.strip.downcase).profile
      raise ArgumentError, "This account needs a profile first" unless profile
      raise ArgumentError, "This account is suspended from the application" if Membership.exists?(site_id: site.id, profile_id: profile.id, status: "suspended")
      LightekCommunity::Audience.authorize!(community.audience, profile: profile, super_admin: profile.user.role == "super_admin")
      community.with_lock do
        record = community.memberships.find_or_initialize_by(profile: profile)
        raise Policy::Denied, "Community ownership cannot be changed here" if record.role == "owner"
        record.update!(role: role)
        audit!("community.member.added", record, fields: ["role"])
      end
    end
    def add_administrator!(email:, role:)
      policy.authorize_admin!("people")
      raise ArgumentError, "Choose an application role" unless Membership::ROLES.include?(role)
      person = User.find_by!(email_address: email.to_s.strip.downcase).profile
      raise ArgumentError, "This account needs a profile first" unless person
      protect_owner!(person)
      Membership.transaction do
        record = Membership.find_or_initialize_by(site_id: site.id, profile_id: person.id)
        record.update!(role: role, status: "active")
        audit!("membership.invited", record, role: role)
      end
    end
    def audit!(action, record, details = {})
      AdminEvent.create!(site: site, actor: user, action: action, record_type: record.class.name, record_id: record.id, details: details)
    end
    private
    def protect_owner!(profile)
      raise Policy::Denied, "The application owner and platform super admins retain authority" if profile.user == site.tenant || profile.user.role.to_s == "super_admin"
    end
    def bool(value) = ActiveModel::Type::Boolean.new.cast(value) == true
  end
end
