module LightekGrowth
  class Workspace
    def initialize(actor:, site:)
      @actor, @site = actor, site
      revalidate!
    end
    def revalidate!
      LightekSales::Access.sites_for(@actor.reload).find(@site.id)
      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
    end
    def save_brief!(values:, version:)
      @site.with_lock do
        revalidate!
        brief = Brief.find_or_initialize_by(site: @site)
        if brief.persisted? && (!version.to_s.match?(/\A\d+\z/) || brief.lock_version != version.to_i)
          raise ActiveRecord::StaleObjectError.new(brief, 'update')
        end
        brief.assign_attributes(values.to_h.stringify_keys.slice(*Brief::FIELDS).merge(updated_by: @actor))
        brief.save!
        log('brief_saved', brief_id: brief.id, revision: brief.lock_version)
        brief
      end
    end
    def create_link!(values:)
      @site.with_lock do
        revalidate!
        values = values.to_h.stringify_keys
        campaign = LightekMarketing::Campaign.where(site: @site).find(values['campaign_id'])
        link = Link.create!(values.slice('label', 'source', 'medium', 'destination_path').merge(site: @site, campaign: campaign, created_by: @actor))
        log('link_created', link_id: link.id, campaign_id: campaign.id)
        link
      end
    end
    def set_enabled!(id:, enabled:)
      @site.with_lock do
        revalidate!
        link = Link.where(site: @site).find(id)
        link.update!(enabled: enabled)
        log(enabled ? 'link_enabled' : 'link_disabled', link_id: link.id)
        link
      end
    end
    private
    def log(event, **fields)
      Rails.logger.info({event: "lightek.growth.#{event}", site_id: @site.id, actor_id: @actor.id}.merge(fields).to_json)
    end
  end
end
