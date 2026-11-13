require 'active_support/security_utils'
require 'openssl'
require 'digest'
require 'securerandom'
module LightekIdentity
  class Mfa
    class Invalid < StandardError; end
    ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'.freeze
    def self.enabled?(user) = Factor.exists?(user_id: user.id).then { |exists| exists && Factor.find_by!(user_id: user.id).enabled? }
    def self.required?(user)
      return true if %w[employee admin super_admin].include?(user.role)
      return true if LightekPeople::Employment.active.where(worker_id: user.id,directory_admin: true).exists?
      employers = LightekPeople::Employment.active.where(worker_id: user.id).pluck(:employer_id)
      employers << user.id
      OrganizationPolicy.where(employer_id: employers,mfa_required: true).exists?
    end
    def self.fresh?(session) = session&.mfa_verified_at && session.mfa_verified_at > 12.hours.ago
    def self.base32(bytes)
      bytes.unpack1('B*').scan(/.{1,5}/).map { |s| ALPHABET[s.ljust(5,'0').to_i(2)] }.join
    end
    def self.decode(secret)
      bits = secret.chars.map { |c| ALPHABET.index(c)&.to_s(2)&.rjust(5,'0') || (raise Invalid, 'Malformed authenticator secret') }.join
      [bits[0,bits.length / 8 * 8]].pack('B*')
    end
    def self.code(secret, counter)
      mac = OpenSSL::HMAC.digest('SHA1', decode(secret), [counter].pack('Q>'))
      offset = mac.getbyte(-1) & 15
      format('%06d', (mac.byteslice(offset,4).unpack1('N') & 0x7fffffff) % 1_000_000)
    end
    def self.begin!(user)
      user.with_lock do
        factor = Factor.find_or_initialize_by(user: user)
        raise Invalid, 'Authenticator is already enabled' if factor.enabled?
        secret = base32(SecureRandom.random_bytes(20))
        factor.update!(secret_box: Sealed.pack({'secret'=>secret}, context: "mfa:#{user.id}"), expires_at: 10.minutes.from_now, last_counter: -1)
        secret
      end
    end
    def self.verify!(user, value, enrolling: false, now: Time.current)
      factor = Factor.find_by!(user: user)
      factor.with_lock do
        raise Invalid, 'Authenticator enrollment expired' if enrolling && (factor.enabled? || !factor.expires_at || factor.expires_at < now)
        raise Invalid, 'Authenticator is not enabled' unless enrolling || factor.enabled?
        input = value.to_s.delete(' -')
        unless enrolling
          digest = Digest::SHA256.hexdigest(input)
          match = factor.recovery_digests.find { |stored| ActiveSupport::SecurityUtils.secure_compare(stored, digest) }
          if match
            factor.update!(recovery_digests: factor.recovery_digests - [match])
            return true
          end
        end
        raise Invalid, 'Invalid or already used authenticator code' unless input.match?(/\A\d{6}\z/)
        secret = Sealed.open(factor.secret_box, context: "mfa:#{user.id}").fetch('secret')
        counter = [-1,0,1].map { |offset| now.to_i / 30 + offset }.find { |c| c > factor.last_counter && ActiveSupport::SecurityUtils.secure_compare(code(secret,c),input) }
        raise Invalid, 'Invalid or already used authenticator code' unless counter
        factor.update!(last_counter: counter)
        if enrolling
          codes = 10.times.map { SecureRandom.hex(12) }
          factor.update!(enabled_at: now, expires_at: nil, recovery_digests: codes.map { |c| Digest::SHA256.hexdigest(c) })
          return codes
        end
        true
      end
    rescue ActiveRecord::RecordNotFound
      raise Invalid, 'Authenticator setup is required'
    end
  end
end
