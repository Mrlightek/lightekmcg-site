class LightekEmailProvisioningService
  DOMAIN = ENV.fetch("LIGHTEK_EMAIL_DOMAIN", "lightekmcg.com").freeze

  class << self
    def provision_for!(user)
      return user.lightek_email_address if user.lightek_email_address.present?

      address = next_available_address(user)
      user.update!(lightek_email_address: address)
      create_mailbox!(user, address)
      address
    end

    private

    def next_available_address(user)
      base = preferred_local_part(user)
      candidate = "#{base}@#{DOMAIN}"
      suffix = 2

      while User.where.not(id: user.id).exists?(lightek_email_address: candidate)
        candidate = "#{base}#{suffix}@#{DOMAIN}"
        suffix += 1
      end

      candidate
    end

    def preferred_local_part(user)
      source = if user.respond_to?(:full_name) && user.full_name.present?
                 user.full_name
               else
                 user.email_address.to_s.split("@").first
               end

      source.parameterize(separator: ".").presence || "member#{user.id}"
    end

    def create_mailbox!(_user, _address)
      # Adapter point for the future Lightek Mail backend.
      true
    end
  end
end
