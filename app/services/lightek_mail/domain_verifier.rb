require "resolv"
module LightekMail
  class DomainVerifier
    def self.verify!(domain)
      records = Resolv::DNS.open do |dns|
        dns.timeouts = 3
        dns.getresources("_lightek-mail.#{domain.name}", Resolv::DNS::Resource::IN::TXT).map(&:data)
      end
      raise ArgumentError, "The ownership TXT record is not visible yet." unless records.include?(domain.verification_value)
      domain.update!(verified_at: Time.current)
    rescue Resolv::ResolvError, Resolv::ResolvTimeout
      raise ArgumentError, "DNS verification could not complete. Try again after DNS propagates."
    end
  end
end
