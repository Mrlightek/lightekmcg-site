module LightekAgency
  class DemoCleanup
    def self.call!(demo)
      demo.with_lock do
        return if demo.cleaned_at
        return if demo.expires_at > Time.current && demo.converted_at.nil?
        # An accepted payment holds the source until provisioning succeeds.
        return if !demo.converted_at && demo.upgrade_order&.paid_at? && demo.upgrade_order.status.in?(%w[paid fulfilled])
        if demo.converted_at
          raise Demos::Invalid, 'Paid instance verification is required before cleanup' unless demo.upgrade_order && LightekCommerce::Installations.ready?(demo.upgrade_order)
        end
        site = demo.site
        raise Demos::Invalid, 'Demo ownership changed; cleanup stopped' if site && (site.tenant != demo.client || site.manifest.to_h['agency_demo'] != demo.public_id)
        if site
          # Never erase settled commerce records, even if they were incorrectly
          # created on a demo site by older code or an external integration.
          if LightekCommerce::Order.where(site: site).where.not(status: %w[pending_payment canceled]).exists?
            raise Demos::Invalid, 'Demo has financial records requiring operator review'
          end
          # Scope every root to this one site. Follow only owned dependent
          # associations, never belongs_to or shared/through relationships.
          Rails.application.eager_load!
          roots = ApplicationRecord.descendants.select do |model|
            reflection = model.reflect_on_association(:site)
            model != Demo && !model.abstract_class? && model.table_exists? && model.column_names.include?('site_id') &&
              reflection && !reflection.polymorphic? && reflection.klass == DymondSite::Site
          end
          roots.each { |model| model.where(site_id: site.id).find_each { |record| destroy_owned!(record, {}) } }
          destroy_owned!(site, {})
        end
        demo.update!(site: nil, status: demo.converted_at ? 'converted' : 'expired', cleaned_at: Time.current, cleanup_error: nil)
        UserFeatureEntitlement.where(user_id: demo.client_id, source: "demo:#{demo.public_id}").destroy_all
      end
      remove_empty_demo_identity!(demo)
    rescue StandardError => error
      demo.update_column(:cleanup_error, "#{error.class}: cleanup needs review".first(250)) if demo.persisted?
      raise
    end
    def self.destroy_owned!(record, seen)
      key = [record.class.name, record.id]
      return if seen[key] || record.destroyed?
      seen[key] = true
      record.class.reflect_on_all_associations.each do |reflection|
        next unless reflection.macro.in?(%i[has_many has_one]) && !reflection.options[:through] &&
          reflection.options[:dependent].in?(%i[destroy destroy_async delete_all restrict_with_error restrict_with_exception])
        children = record.public_send(reflection.name)
        Array(children.respond_to?(:to_a) ? children.to_a : children).compact.each do |child|
          if child.class.name == 'ActiveStorage::Attachment'
            child.purge_later
          else
            destroy_owned!(child, seen)
          end
        end
      end
      record.destroy!
    end
    def self.remove_empty_demo_identity!(demo)
      return unless demo.created_client? && !demo.upgrade_order_id && demo.client
      client = demo.client
      return if Demo.where(client: client, cleaned_at: nil).exists? || DymondSite::Site.where(tenant: client).exists?
      return if LightekCommerce::Order.where(customer_email: client.email_address).or(LightekCommerce::Order.where(hosting_owner: client)).exists?
      # Never cascade into an account that has acquired real business resources.
      return if client.bank_accounts.exists? || client.subscription || client.invoices.exists? || client.payouts.exists? || client.agency_clients.exists?
      client.with_lock do
        client.sessions.destroy_all
        LightekIdentity::Factor.where(user_id: client.id).destroy_all
        client.destroy!
      end
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      demo.update_column(:cleanup_error, 'Demo workspace removed; client identity retained because it has other business records.')
    end
  end
end
