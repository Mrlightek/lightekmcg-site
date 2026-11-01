# frozen_string_literal: true
require "ipaddr"

module LightekSettings
  class SiteDomain
    class Invalid < ArgumentError; end

    def self.public_hostname!(value)
      host = value.to_s.strip.downcase.delete_suffix(".")
      labels = host.split(".", -1)
      valid = host.bytesize <= 253 && labels.length >= 2 && labels.all? { |label| label.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) }
      valid &&= !labels.last.match?(/\A\d+\z/) && !%w[local localhost internal].include?(labels.last) && !host.end_with?(".home.arpa")
      raise Invalid, "Use a public DNS hostname, such as your-company.com; IP addresses, URLs and local hostnames are not website domains" unless valid
      host
    end

    def self.public_hostname?(value)
      public_hostname!(value)
      true
    rescue Invalid
      false
    end

    def self.verify!(host:)
      domain = public_hostname!(host)
      site = DymondSite::Site.find_by(host: domain)
      raise Invalid, "No website is bound to #{domain}. Repair the website hostname in PWA Administration before releasing this installation." unless site
      LightekPwa::Application.find_or_create_by!(site: site) { |app| app.name = site.name }
      site
    end

    # Repair an imported development identity, not a managed customer's DNS or
    # infrastructure reservation. Those changes belong to Network & Domains.
    def self.repair!(site:, actor:, host:, expected_host:)
      raise LightekPwa::Policy::Denied, "Hostname repair requires a platform super admin" unless actor&.role.to_s == "super_admin"
      domain = public_hostname!(host)
      site.with_lock do
        raise Invalid, "The website hostname changed. Reload before repairing it." unless site.host == expected_host
        raise Invalid, "This website already has a public domain. Use Network & Domains to change it." if public_hostname?(site.host)
        raise Invalid, "This website is managed by provisioning. Repair its domain through Network & Domains." if site.manifest.to_h["hosted_application_key"].present? || site.manifest.to_h["lightek_website_bootstrap"].present?
        raise Invalid, "Another website already uses #{domain}; no website was changed." if DymondSite::Site.where(host: domain).where.not(id: site.id).exists?
        previous = site.host
        site.update!(host: domain)
        LightekPwa::AdminEvent.create!(site: site, actor: actor, action: "website.hostname.repaired", record_type: site.class.name, record_id: site.id, details: {previous_host: previous, host: domain})
      end
      site
    rescue ActiveRecord::RecordNotUnique
      raise Invalid, "Another website already uses #{domain}; no website was changed."
    end
  end
end
