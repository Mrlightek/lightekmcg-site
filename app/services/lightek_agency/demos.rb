module LightekAgency
  class Demos
    class Invalid < StandardError; end
    def self.agencies(actor)
      raise Invalid, 'Agency access required' unless actor&.role.in?(%w[super_admin white_label])
      actor.role == 'super_admin' ? User.where(role: %w[super_admin white_label]) : User.where(id: actor.managed_account_ids, role: 'white_label')
    end
    def self.scope(actor)
      return Demo.none unless actor
      return Demo.all if actor.role == 'super_admin'
      return Demo.where(agency_id: actor.managed_account_ids).or(Demo.where(client_id: actor.id)) if actor.role == 'white_label'
      Demo.where(client_id: actor.id)
    end
    def self.upgrade_products(agency)
      sites = DymondSite::Site.where(tenant_type: 'User', tenant_id: [agency.id] + User.where(role: 'super_admin').pluck(:id))
      LightekCommerce::Product.visible.where(site_id: sites.select(:id), product_type: 'lightek_instance').where.not(subscription_plan_id: nil)
    end
    def self.create!(agency:, values:, existing_client: nil, request: nil)
      raise Invalid, 'An agency or platform operator is required' unless agency.role.in?(%w[white_label super_admin])
      demo = nil
      agency.with_lock do
        setting = DemoSetting.find_or_create_by!(agency: agency)
        return request.demo if request&.demo
        raise Invalid, 'This agency has reached its active demo limit' if Demo.where(agency: agency, cleaned_at: nil).count >= setting.max_active
        if existing_client
          raise Invalid, 'Choose a direct client of this agency' unless existing_client.role == 'client' && existing_client.agency_id == agency.id
          raise Invalid, 'This client already has a demo' if Demo.where(client: existing_client, cleaned_at: nil).exists?
          raise Invalid, 'Use a separate demo account for a client with an existing workspace' if DymondSite::Site.where(tenant: existing_client).exists? || LightekAccounting::Book.where(employer: existing_client).exists?
        end
        created = existing_client.nil?
        client = existing_client || User.create!(values.slice(:first_name, :last_name, :email_address).merge(
          agency: agency, role: 'client', password_setup_required: true, password: SecureRandom.urlsafe_base64(36),
          skip_password_setup_invitation: request.present?))
        demo = Demo.new(agency: agency, client: client, demo_request: request, created_client: created,
          name: values[:name].presence || "#{client.first_name}'s demo", expires_at: setting.duration_days.days.from_now)
        demo.save!
        site = DymondSite::Site.create!(tenant: client, name: demo.name, host: "demo-#{demo.public_id}.invalid",
          manifest: {'agency_demo' => demo.public_id})
        page = site.pages.find_or_initialize_by(slug: 'home')
        page.update!(title: 'Home', position: 0, published: false)
        page.sections.create!(kind: 'hero', position: 0, data: {'heading' => demo.name, 'subheading' => 'Make this workspace yours. Your demo website can move with you when you upgrade.'})
        demo.update!(site: site)
        request&.update!(status: 'activated', verified_at: Time.current)
      end
      begin
        DemoCleanupJob.set(wait_until: demo.expires_at).perform_later(demo.id)
      rescue StandardError => error
        Rails.logger.warn("[Demos] expiry enqueue failed demo=#{demo.id} #{error.class}; periodic sweep will recover")
      end
      demo
    end
    def self.public_setting(host)
      site = DymondSite::Site.find_by!(host: host)
      DemoSetting.find_by!(agency: site.tenant, public_site: site, public_enabled: true)
    end
    def self.ensure_live_site!(site, error: Invalid)
      return unless Demo.table_exists?
      raise error, 'Demo workspaces cannot accept real orders or send live campaigns. Upgrade to your own instance first.' if Demo.exists?(site_id: site.id)
    end
    def self.hidden_site_ids
      Demo.where.not(site_id: nil).where.not(id: Demo.available.select(:id)).select(:site_id)
    end
    def self.expired_demo_account?(user)
      return false unless user&.role == 'client' && Demo.table_exists?
      records = Demo.where(client_id: user.id, created_client: true)
      records.exists? && !records.available.exists?
    end
  end
end
