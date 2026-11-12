# frozen_string_literal: true
module LightekMarketing
  class StudioProduction
    # The existing project request key makes retries open the same editable
    # production. Each collaborator owns a production; site policy still applies.
    def self.open!(campaign:, actor:)
      LightekAgency::Access.sites_for(actor).find(campaign.site_id)
      Studio::Broadcasting::Access.authorize!(actor, campaign.site)
      campaign.with_lock do
        result = Studio::Workers::Workspace.perform("project_create", {
          "user_id" => actor.id, "site_id" => campaign.site_id,
          "request_key" => "campaign-#{campaign.id}-actor-#{actor.id}",
          "name" => campaign.name.truncate(120),
          "format" => campaign.channel == "social" ? "portrait" : "landscape"
        })
        scene = Studio::PwaAccess.new("user_id" => actor.id, "site_id" => campaign.site_id).scene!(result.fetch(:scene_id))
        scene.with_lock do
          unless scene.settings["campaign_id"]
            settings = scene.settings.deep_dup
            settings["campaign_id"] = campaign.id
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
