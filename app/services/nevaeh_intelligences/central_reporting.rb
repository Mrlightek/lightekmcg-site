# frozen_string_literal: true
require "net/http"
require "openssl"
require "active_support/security_utils"
require "json"
module NevaehIntelligences
  module CentralReporting
    class Invalid < WorkOrder::Invalid; end
    CONSUMER = "nevaeh-central-reporting"
    PURPOSE = "nevaeh_escalation"
    KEYS = %w[NEVAEH_CENTRAL_URL NEVAEH_INSTALLATION_ID NEVAEH_CENTRAL_TOKEN].freeze
    module_function

    def settings
      NevaehCapability.find_by(slug: StructuredTicket::CAPABILITY)&.metadata.to_h.fetch("central_reporting", {})
    end

    def client?
      KEYS.any? { |key| ENV[key].present? }
    end

    def signature(token, timestamp, body)
      OpenSSL::HMAC.hexdigest("SHA256", token, "#{timestamp}.#{body}")
    end

    def credential(installation)
      LightekVault::Service.checkout!(slug: installation.nevaeh_reporting_secret_slug, consumer: CONSUMER,
        purpose: PURPOSE, requested_by: "nevaeh-installation:#{installation.id}").fetch("token")
    end

    def authenticate!(installation_id:, timestamp:, supplied:, body:)
      raise Invalid, "Unauthorized installation report" unless settings["enabled"] == true && body.bytesize <= 64000 &&
        installation_id.to_s.match?(/\A[1-9][0-9]*\z/) && timestamp.to_s.match?(/\A[0-9]{10}\z/) && supplied.to_s.match?(/\A[0-9a-f]{64}\z/) &&
        (Time.now.to_i - timestamp.to_i).abs <= 300
      installation = GatekeeperInstallation.find(installation_id)
      raise Invalid, "Unauthorized installation report" unless installation.eligible? && installation.nevaeh_reporting_secret_slug.present?
      expected = signature(credential(installation), timestamp, body)
      raise Invalid, "Unauthorized installation report" unless ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
      installation
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
      raise Invalid, "Unauthorized installation report"
    end

    def receive!(installation:, payload:)
      raise Invalid, "Escalation report must be an object" unless payload.is_a?(Hash)
      source = payload.deep_stringify_keys
      raise Invalid, "Unsupported escalation report" unless source["version"] == 1 && source["ticket_id"].is_a?(Integer) && source["ticket_id"].positive?
      %w[number title description reason].each do |key|
        maximum = {"number" => 100, "title" => 1000, "description" => 20000, "reason" => 4000}.fetch(key)
        raise Invalid, "Invalid escalation #{key}" unless source[key].is_a?(String) && source[key].bytesize <= maximum
      end
      raise Invalid, "Escalation title and reason are required" if source["title"].blank? || source["reason"].blank?
      source = source.slice("version", "ticket_id", "number", "title", "description", "reason", "work_order", "knowledge_article_ids")
      digest = TicketApproval.fingerprint(source)
      ticket = nil
      installation.with_lock do
        ticket = Marlon::Ticket.where(related: installation).where("CAST(extra_fields -> 'nevaeh_remote' ->> 'ticket_id' AS TEXT) = ?", source.fetch("ticket_id").to_s).first
        unless ticket
          ticket = Marlon::Ticket.create!(title: "#{installation.domain}: #{source.fetch('title')}", description: source.fetch("description"),
            category: "technical", priority: "high", urgency: 8, status: "open", submitted_by: installation.account, related: installation,
            extra_fields: {"source" => "nevaeh_remote", "nevaeh_remote" => {"installation_id" => installation.id,
              "account_id" => installation.account_id, "domain" => installation.domain, "ticket_id" => source.fetch("ticket_id"),
              "payload" => source, "source_sha256" => digest, "received_at" => Time.current.iso8601}})
          ticket.log!(action: "nevaeh_client_escalation_received", detail: {"installation_id" => installation.id, "remote_ticket_id" => source.fetch("ticket_id")}.to_json)
        end
        if ticket.extra_fields.dig("nevaeh_remote", "source_sha256") != digest
          raise Invalid, "The originating ticket changed; central support must review its existing report"
        end
      end
      NevaehOrchestration::Escalation.knowledge_gap!(ticket: ticket, reason: source.fetch("reason"))
      ticket
    end

    def deliver!(ticket:)
      raise Invalid, "Client escalation reporting is not fully configured" unless KEYS.all? { |key| ENV[key].present? }
      uri = URI(ENV.fetch("NEVAEH_CENTRAL_URL"))
      raise Invalid, "The central reporting endpoint must be HTTPS without credentials or redirects" unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && !uri.fragment && !uri.query && uri.path.end_with?("/gatekeeper/callbacks/nevaeh_escalation")
      body = nil
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        gap = fields.fetch("nevaeh_knowledge_gap")
        return if gap.dig("notification", "state") == "reported_to_central"
        notification = gap.fetch("notification")
        notification["report_body"] ||= JSON.generate({"version" => 1, "ticket_id" => ticket.id, "number" => ticket.number,
          "title" => ticket.title, "description" => ticket.description.to_s, "reason" => gap.fetch("reason"),
          "work_order" => fields["nevaeh_work_order"], "knowledge_article_ids" => fields.dig("nevaeh_backlog", "knowledge_article_ids")})
        body = notification.fetch("report_body")
        raise Invalid, "The escalation report exceeds 64 KB; support must review its attachments locally" if body.bytesize > 64000
        ticket.update!(extra_fields: fields)
      end
      timestamp = Time.now.to_i.to_s
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Lightek-Installation"] = ENV.fetch("NEVAEH_INSTALLATION_ID")
      request["X-Lightek-Timestamp"] = timestamp
      request["X-Lightek-Signature"] = signature(ENV.fetch("NEVAEH_CENTRAL_TOKEN"), timestamp, body)
      request.body = body
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
      raise Invalid, "Central support rejected or could not receive the report (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
      receipt = JSON.parse(response.body)
      raise Invalid, "Central support returned an invalid receipt" unless receipt["ticket_id"].is_a?(Integer) && receipt["ticket_id"].positive?
      ticket.with_lock do
        fields = ticket.extra_fields.to_h.deep_stringify_keys
        notification = fields.fetch("nevaeh_knowledge_gap").fetch("notification")
        return if notification["state"] == "reported_to_central"
        raise Invalid, "Escalation snapshot changed while reporting" unless notification["report_body"] == body
        notification.merge!("state" => "reported_to_central", "central_ticket_id" => receipt.fetch("ticket_id"), "reported_at" => Time.current.iso8601)
        notification.delete("blocker")
        ticket.update!(extra_fields: fields)
        ticket.log!(action: "nevaeh_escalation_forwarded_to_central", detail: receipt.slice("ticket_id", "ticket_number").to_json)
      end
    rescue JSON::ParserError, URI::InvalidURIError
      raise Invalid, "Invalid central escalation endpoint or response"
    end
  end
end
