# frozen_string_literal: true
module LightekMarketing
  class StudioProduction
    def self.production_brief(campaign)
      brief = LightekGrowth::Brief.find_by(site_id: campaign.site_id) if defined?(LightekGrowth::Brief) && LightekGrowth::Brief.table_exists?
      approved = ContentVariant.where(campaign: campaign, status: 'approved', applied_digest: campaign.approved_content_digest).order(id: :desc).first if campaign.has_attribute?(:content_review_required) && campaign.content_review_required? && campaign.content_approved?
      context = approved ? approved.source_snapshot.fetch('brief') : {'audience' => brief&.audience, 'goal' => brief&.goal}
      {'offer' => campaign.headline, 'audience' => context['audience'], 'business_goal' => context['goal'], 'call_to_action' => campaign.cta_label, 'destination' => campaign.cta_url,
       'format' => format_for(campaign), 'content_digest' => campaign.content_digest}
    end
    def self.format_for(campaign) = campaign.channel == "social" ? (campaign.has_attribute?(:production_format) ? campaign.production_format : "portrait") : "landscape"
    def self.sync_brief!(campaign:, actor:)
      scene = open!(campaign: campaign, actor: actor)
      campaign.with_lock do
        scene.with_lock do
          settings = scene.settings.deep_dup
          settings['workspace'] ||= {}
          settings['workspace']['story'] ||= {}
          settings['workspace']['story']['scriptDraft'] = [campaign.headline, campaign.message, campaign.cta_label, campaign.cta_url].compact_blank.join("\n\n")
          settings['campaign_content_digest'] = campaign.content_digest
          settings['campaign_content_approved'] = campaign.has_attribute?(:content_review_required) && campaign.content_review_required? && campaign.content_approved?
          settings['campaign_production_brief'] = production_brief(campaign)
          scene.update!(settings: settings)
        end
      end
      scene
    end
    # The existing project request key makes retries open the same editable
    # production. Each collaborator owns a production; site policy still applies.
    def self.open!(campaign:, actor:)
      LightekSales::Access.sites_for(actor.reload).find(campaign.site_id)
      Studio::Broadcasting::Access.authorize!(actor, campaign.site)
      campaign.with_lock do
        result = Studio::Workers::Workspace.perform("project_create", {
          "user_id" => actor.id, "site_id" => campaign.site_id,
          "request_key" => "campaign-#{campaign.id}-actor-#{actor.id}",
          "name" => campaign.name.truncate(120),
          "format" => format_for(campaign)
        })
        scene = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => campaign.site_id).scene!(result.fetch(:scene_id))
        scene.with_lock do
          unless scene.settings["campaign_id"]
            settings = scene.settings.deep_dup
            settings["campaign_id"] = campaign.id
            settings["campaign_content_digest"] = campaign.content_digest
            settings["campaign_content_approved"] = campaign.has_attribute?(:content_review_required) && campaign.content_review_required? && campaign.content_approved?
            settings["campaign_production_brief"] = production_brief(campaign)
            settings["editor_kind"] = "video"
            settings["workspace"] ||= {}
            settings["workspace"]["story"] ||= {}
            settings["workspace"]["story"]["scriptDraft"] ||= [campaign.headline, campaign.message, campaign.cta_label, campaign.cta_url].compact_blank.join("\n\n")
            scene.update!(settings: settings)
          end
        end
        scene
      end
    end
  end
end
