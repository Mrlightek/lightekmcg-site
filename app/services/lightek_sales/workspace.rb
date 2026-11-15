# frozen_string_literal: true
module LightekSales
  class Workspace
    RECORDS = {'lead' => Lead, 'account' => Account, 'contact' => LightekMarketing::Contact, 'opportunity' => Opportunity, 'routing_rule' => RoutingRule}.freeze
    FIELDS = {
      'lead' => %w[name email company phone source status owner_id next_step follow_up_on notes],
      'account' => %w[name website owner_id notes],
      'contact' => %w[name email phone job_title sales_account_id sales_owner_id sales_notes],
      'opportunity' => %w[name account_id contact_id owner_id stage amount amount_cents currency probability close_on next_step follow_up_on notes forecast_category loss_reason],
      'routing_rule' => %w[source owner_id]
    }.freeze
    attr_reader :actor, :site
    def initialize(actor:, site:)
      @actor, @site = actor, Access.sites_for(actor).find(site.id)
    end
    def scope(kind)
      RECORDS.fetch(kind).where(site: site)
    end
    def find(kind, id) = scope(kind).find(id)

    def save!(kind, values, id: nil, lock_version: nil)
      authorize_routing! if kind == 'routing_rule'
      record = id ? find(kind, id) : scope(kind).new
      record.with_lock do
        if id && (lock_version.blank? || record.lock_version != Integer(lock_version.to_s, 10))
          raise ActiveRecord::StaleObjectError.new(record, 'update')
        end
        attributes = values.to_h.stringify_keys.slice(*FIELDS.fetch(kind))
        if kind == 'contact' && record.persisted? && attributes.key?('email') && attributes['email'].to_s.strip.downcase != record.email
          raise ArgumentError, 'Keep the existing contact email to preserve its consent history. Create another contact for a different address.'
        end
        if kind == 'lead' && record.new_record? && attributes['owner_id'].blank?
          attributes['owner_id'] = routed_owner(attributes['source'])&.id
        end
        created = record.new_record?
        attributes = parse_money(attributes) if kind == 'opportunity'
        record.assign_attributes(attributes)
        record.save!
        changes = record.saved_changes.except('created_at', 'updated_at', 'lock_version')
        description = created ? 'Record created.' : "Updated #{changes.keys.join(', ')}."
        if changes['stage']
          description += " Stage: #{changes['stage'].first || 'new'} → #{changes['stage'].last}."
        end
        log!(record, created ? 'created' : 'updated', description)
      end
      record
    end

    def convert!(lead_id, values, lock_version:)
      lead = find('lead', lead_id)
      # Serializes matching company/contact creation for this website, including
      # two different leads converted into the same company at the same time.
      site.with_lock do
        lead.reload
        return lead.opportunity if lead.converted_at?
        if lock_version.blank? || lead.lock_version != Integer(lock_version.to_s, 10)
          raise ActiveRecord::StaleObjectError.new(lead, 'convert')
        end
        raise ArgumentError, 'Qualify this lead before converting it.' unless lead.status == 'qualified'
        attributes = values.to_h.stringify_keys.slice('name', 'amount', 'amount_cents', 'currency', 'close_on')
        attributes = parse_money(attributes)
        contact = LightekMarketing::Contact.find_or_initialize_by(site: site, email: lead.email)
        account = contact.sales_account || scope('account').find_or_initialize_by(normalized_name: lead.company.strip.downcase)
        if account.new_record?
          account.assign_attributes(name: lead.company, owner_id: eligible_owner(lead.owner_id)&.id)
          account.save!
          log!(account, 'created', "Created from lead ##{lead.id}.")
        end
        contact.name = lead.name if contact.name.blank?
        contact.phone = lead.phone if contact.phone.blank?
        contact.sales_account = account
        contact.sales_owner_id = eligible_owner(lead.owner_id)&.id if contact.sales_owner_id.blank?
        contact.save!
        opportunity = scope('opportunity').create!(attributes.merge(account: account, contact: contact,
          owner_id: eligible_owner(lead.owner_id)&.id, stage: 'qualified', probability: 30,
          next_step: lead.next_step, follow_up_on: lead.follow_up_on, notes: lead.notes))
        lead.update!(status: 'converted', converted_at: Time.current, opportunity: opportunity)
        log!(lead, 'converted', "Converted to deal ##{opportunity.id}; company ##{account.id}, contact ##{contact.id}.")
        log!(opportunity, 'created', "Created from lead ##{lead.id}.")
        opportunity
      end
    end

    def activity!(kind, id, activity_kind:, body:)
      record = find(kind, id)
      raise ArgumentError, 'Choose a note, call, meeting or email.' unless activity_kind.in?(%w[note call meeting email])
      log!(record, activity_kind, body)
    end

    private
    def parse_money(attributes)
      return attributes unless attributes.key?('amount')
      value = attributes.delete('amount').to_s.strip
      raise ArgumentError, 'Enter a nonnegative deal value with up to two decimal places.' unless value.match?(/\A\d{1,14}(?:\.\d{1,2})?\z/)
      attributes.merge('amount_cents' => (BigDecimal(value) * 100).to_i)
    end
    def authorize_routing!
      raise ActiveRecord::RecordNotFound unless LightekAgency::Access.manage_members?(actor, site)
    end
    def eligible_owner(id) = Access.owners_for(site).find_by(id: id)
    def routed_owner(source)
      rule = scope('routing_rule').find_by(source: source.to_s.strip.downcase.presence || 'manual')
      eligible_owner(rule&.owner_id) || eligible_owner(actor.id) || eligible_owner(site.tenant_id)
    end
    def log!(record, kind, body)
      Activity.create!(site: site, actor: actor, record: record, kind: kind, body: body)
    end
  end
end
