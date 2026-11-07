module Gatekeeper
  module Hosting
    class MailPortRequest
      def self.description(ip:, domain:, hostname:)
        "I am configuring a legitimate transactional and inbound mail server on my Linode at #{ip} for the domain #{domain}.\n\n" \
          "The server hostname is #{hostname}. It will be used for account notifications, invitations, and other transactional application email, including invitations for our software services.\n\n" \
          "Please remove the outbound SMTP restrictions on ports 25, 465, and 587 for my account/Linode.\n\n" \
          "I will configure SPF, DKIM, DMARC, reverse DNS, rate limits, and abuse protections before production mail is sent."
      end

      def self.submit!(request:, actor:, domain:)
        return unless request.compute_provider&.slug == "linode"
        request.with_lock do
          return if request.metadata.to_h["mail_port_ticket_id"].present?
          node = request.gatekeeper_node
          ticket = request.compute_provider.adapter(requested_by: actor.email_address).create_support_ticket(
            summary: "Remove outbound SMTP restrictions for #{domain}", linode_id: node.provider_resource_id,
            description: description(ip: node.ip_address, domain: domain, hostname: node.hostname.presence || domain))
          raise "Mail port support ticket response missing ID" if ticket["id"].blank?
          request.update!(metadata: request.metadata.to_h.merge("mail_port_ticket_attempted" => true,
            "mail_port_ticket_id" => ticket["id"], "mail_port_ticket_status" => "submitted"))
        end
      end
    end
  end
end
