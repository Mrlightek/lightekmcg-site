# frozen_string_literal: true
require 'csv'
require 'digest'
module LightekSales
  class Intake
    CSV_HEADERS = %w[name email company phone message source].freeze
    attr_reader :workspace, :actor, :site
    def initialize(actor:, site:)
      @workspace = Workspace.new(actor: actor, site: site)
      @actor, @site = actor, @workspace.site
    end

    def stage_csv!(raw)
      raise ArgumentError, 'Upload a UTF-8 CSV smaller than 512 KB.' if raw.to_s.bytesize > 512_000
      raw = raw.to_s.dup.force_encoding(Encoding::UTF_8)
      raise ArgumentError, 'Upload a UTF-8 CSV without null bytes.' unless raw.valid_encoding? && !raw.include?("\0")
      raw = raw.sub(/\A\uFEFF/, '')
      rows = CSV.parse(raw, headers: true)
      headers = rows.headers.to_a
      unless (headers - CSV_HEADERS).empty? && headers.uniq == headers && %w[name email].all? { |h| headers.include?(h) }
        raise ArgumentError, 'CSV headers must include name,email; optional company,phone,message,source. Use each header once.'
      end
      raise ArgumentError, 'Upload between 1 and 100 data rows per file.' unless rows.size.in?(1..100)
      digest = Digest::SHA256.hexdigest(raw)
      site.with_lock do
        rows.each_with_index.map do |row, index|
          raise ArgumentError, 'Each CSV row must match the header columns.' if row.fields.length != headers.length || row.headers.any?(&:nil?)
          values = row.to_h.transform_values { |v| v.to_s.strip }
          raise ArgumentError, 'Keep each CSV value under 2000 characters.' if values.values.any? { |v| v.length > 2000 }
          IntakeEntry.find_or_create_by!(site: site, origin_key: "csv:#{digest}:#{index + 1}") do |entry|
            entry.assign_attributes(origin: 'csv', source: values['source'].presence || 'csv', created_by: actor,
              original: values, payload: values.slice(*IntakeRule::TARGETS))
          end
        end
      end
    rescue CSV::MalformedCSVError
      raise ArgumentError, 'The CSV could not be read. Check quoting and use one header row.'
    end

    def capture!(inquiry_id, rule: nil)
      inquiry = WebsiteTemplateInquiry.where(site: site).find(inquiry_id)
      if rule
        raise ActiveRecord::RecordNotFound unless rule.site_id == site.id && rule.template_key == inquiry.template_key && rule.section_key == inquiry.section_key
      end
      mapping = rule ? rule.mapping : IntakeRule::TARGETS.to_h { |key| [key, key == 'message' && inquiry.fields.key?('msg') ? 'msg' : key] }
      values = mapping.to_h { |key, field| [key, inquiry.fields[field].to_s.strip] }.slice(*IntakeRule::TARGETS)
      site.with_lock do
        IntakeEntry.find_or_create_by!(site: site, origin_key: "website:#{inquiry.id}") do |entry|
          source = if inquiry.sales_partner_id?
            'partner_referral'
          else
            rule&.source || (inquiry.native_sales_form? ? 'sales_inquiry' : 'website')
          end
          entry.assign_attributes(origin: 'website', inquiry: inquiry, source: source,
            payload: values, original: inquiry.fields, created_by: actor)
        end
      end
    end

    def process!(id, lock_version:, values: {})
      site.with_lock do
        entry = IntakeEntry.where(site: site).find(id)
        return entry if entry.processed?
        check_version!(entry, lock_version)
        data = entry.payload.merge(values.to_h.stringify_keys.slice(*IntakeRule::TARGETS).transform_values { |v| v.to_s.strip })
        unless data['name'].present? && data['name'].length <= 160 && data['email'].to_s.match?(URI::MailTo::EMAIL_REGEXP) && data['email'].length <= 254
          raise ArgumentError, 'Enter a name (up to 160 characters) and a valid email before accepting this inquiry.'
        end
        entry.update!(payload: data)
        # A new inquiry does not revise an existing relationship, reopen a lost
        # sale, or change a converted lead. Preserve it as a new attributed event.
        lead = Lead.find_by(site: site, email: data['email'].to_s.strip.downcase)
        duplicate = lead.present?
        unless lead
          lead = workspace.save!('lead', {name: data['name'], email: data['email'], company: data['company'].presence || data['name'],
            phone: data['phone'], source: entry.source, notes: details(entry, data),
            next_step: 'Review the inquiry and agree on a first conversation.', follow_up_on: Date.current + 1}, growth_visit: entry.inquiry&.growth_attribution)
        end
        if !duplicate && entry.inquiry&.sales_partner_id? &&
            entry.inquiry.fields['email'].to_s.strip.casecmp?(lead.email)
          partner = entry.inquiry.sales_partner
          Referral.create!(partner: partner, lead: lead, commission_cents: partner.commission_cents)
        end
        Activity.create!(site: site, actor: actor, record: lead, kind: 'inquiry_received', body: details(entry, data))
        related = lead.converted_at? ? lead.opportunity : lead
        kind = related.is_a?(Opportunity) ? 'opportunity' : 'lead'
        owner = Access.owners_for(site).find_by(id: related.owner_id) || Access.owners_for(site).find_by(id: actor.id) || Access.owners_for(site).first
        raise ArgumentError, 'Add an eligible sales owner before accepting this inquiry.' unless owner
        Tasks.new(actor: actor, site: site).create!(kind: kind, id: related.id,
          values: {title: "Review new inquiry from #{data['name'].presence || lead.name}".first(300), owner_id: owner.id, due_at: Time.current + 1.day}, source_key: "intake:#{entry.id}")
        entry.update!(lead: lead, status: duplicate ? 'duplicate' : 'imported', processed_by: actor, processed_at: Time.current, error_message: nil)
        entry
      end
    end

    def ignore!(id, lock_version:)
      entry = IntakeEntry.where(site: site).find(id)
      entry.with_lock do
        check_version!(entry, lock_version)
        raise ArgumentError, 'An accepted inquiry cannot be ignored.' if entry.lead_id.present?
        entry.update!(status: 'ignored', processed_by: actor, processed_at: Time.current)
      end
      entry
    end

    def save_rule!(values, id: nil, lock_version: nil)
      raise ActiveRecord::RecordNotFound unless LightekAgency::Access.manage_members?(actor, site)
      site.with_lock do
        rule = id ? IntakeRule.where(site: site).find(id) : IntakeRule.new(site: site)
        check_version!(rule, lock_version) if id
        rule.assign_attributes(values.to_h.stringify_keys.slice('template_key', 'section_key', 'source', 'mapping', 'enabled'))
        if rule.enabled? && !self.class.published_form?(site, rule.template_key, rule.section_key)
          raise ArgumentError, 'Publish this form on the selected website before enabling intake.'
        end
        rule.save!
        rule
      end
    end

    def self.published_form?(site, template, section)
      site.pages.where(published: true).joins(:sections).where("dymond_site_sections.data ->> 'template_key' = ? AND dymond_site_sections.data ->> 'section_key' = ?", template, section).exists?
    end

    private
    def check_version!(record, version)
      unless version.to_s.match?(/\A\d+\z/) && record.lock_version == version.to_i
        raise ActiveRecord::StaleObjectError.new(record, 'update')
      end
    end
    def details(entry, data)
      "#{entry.origin.humanize} inquiry · #{entry.source} · intake ##{entry.id}\n" + data.map { |key, value| "#{key.humanize}: #{value}" }.join("\n")
    end
  end
end
