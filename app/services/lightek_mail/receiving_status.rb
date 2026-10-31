require "resolv"
module LightekMail
  class ReceivingStatus
    def self.check(account)
      return {ok: false, message: "Enable this mailbox before receiving mail."} unless account.enabled?
      return {ok: false, message: "Verify ownership of #{account.domain.name} before receiving mail."} unless account.domain.verified_at
      host = ENV.fetch("LIGHTEK_MAIL_HOST", "mail.lightekmcg.com").downcase.delete_suffix(".")
      exchanges = Resolv::DNS.open do |dns|
        dns.timeouts = 2
        dns.getresources("#{account.domain.name}.", Resolv::DNS::Resource::IN::MX).map { |record| record.exchange.to_s.downcase.delete_suffix(".") }
      end
      unless exchanges.include?(host)
        return {ok: false, message: "Incoming mail for #{account.domain.name} is routed to #{exchanges.empty? ? 'no MX server' : exchanges.join(', ')}. Expected MX: #{host}. Update the domain’s MX records to receive mail here."}
      end
      {ok: true, message: "MX points to #{host}. DNS check passed; this does not test SMTP delivery. If messages are missing, check port 25, recipient synchronization and the Postfix HTTPS ingress queue."}
    rescue Resolv::ResolvError, Resolv::ResolvTimeout, SocketError, IOError, SystemCallError
      {ok: false, message: "The receiving DNS check could not complete. Try again shortly."}
    end
  end
end
