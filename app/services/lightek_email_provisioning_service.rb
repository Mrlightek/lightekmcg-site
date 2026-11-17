class LightekEmailProvisioningService
  DOMAIN = ENV.fetch('LIGHTEK_EMAIL_DOMAIN', 'lightekmcg.com').freeze
  class Unavailable < StandardError; end
  def self.domain!
    raise Unavailable, 'Member email is not open yet' unless ENV['LIGHTEK_MEMBER_EMAIL_ENABLED'] == 'true'
    domain = LightekMail::Domain.find_by(name: DOMAIN)
    raise Unavailable, 'The Lightek mail domain must be verified by the platform owner' unless domain&.verified_at && domain.user.role == 'super_admin'
    domain
  end
  def self.provision_for!(user)
    # Old Susu entry points may call this before email confirmation. Do not
    # advertise a usable address when no real mailbox has been provisioned.
    return nil unless user.lightek_email_confirmed_at
    domain = domain!
    account = nil
    domain.with_lock do
      user.with_lock do
        account = LightekMail::Account.mailboxes.find_by(user: user, brand_member: true, domain: domain)
        unless account
          base = (user.full_name.presence || "member#{user.id}").parameterize(separator: '.').first(45)
          base = "member#{user.id}" if base.blank? || %w[admin administrator support postmaster abuse security hostmaster webmaster billing noreply].include?(base)
          suffix = 1
          loop do
            address = "#{base}#{suffix == 1 ? '' : suffix}@#{DOMAIN}"
            used = LightekMail::Account.where(address: address).or(LightekMail::Account.where(original_address: address)).exists? || User.where.not(id: user.id).exists?(lightek_email_address: address)
            unless used
              user.update!(lightek_email_address: address)
              account = LightekMail::Account.create!(user: user, domain: domain, address: address,
                display_name: user.full_name.first(120), enabled: true, brand_member: true,
                storage_limit: 250.megabytes, minute_limit: 2, hour_limit: 10, daily_limit: 20)
              break
            end
            suffix += 1
          end
        end
      end
    end
    account.address
  end
  def self.confirm!(user)
    domain!.with_lock do
      user.update!(lightek_email_confirmed_at: Time.current)
      provision_for!(user)
    end
  end
end
