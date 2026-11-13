require 'active_support/security_utils'
require 'jwt'
require 'digest'
require 'securerandom'
require 'base64'
module LightekIdentity
  class Oidc
    class Invalid < StandardError; end
    def self.slug(connection) = "identity-oidc-#{connection.employer_id}"
    def self.start!(connection:, browser:, redirect_uri:, linking_user: nil)
      raise Invalid, 'Organization sign-in is disabled' unless connection.enabled?
      state, nonce, verifier = SecureRandom.hex(32), SecureRandom.hex(24), SecureRandom.urlsafe_base64(48)
      digest = Digest::SHA256.hexdigest(state)
      LoginAttempt.create!(connection: connection, user: linking_user, state_digest: digest,
        browser_digest: Digest::SHA256.hexdigest(browser), expires_at: 5.minutes.from_now,
        secret_box: Sealed.pack({'nonce'=>nonce,'verifier'=>verifier,'redirect_uri'=>redirect_uri}, context: "oidc:#{digest}"))
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      uri = URI.parse(connection.authorization_endpoint)
      query = URI.decode_www_form(uri.query.to_s).to_h
      query.merge!({'client_id'=>connection.client_id, 'response_type'=>'code','scope'=>'openid','redirect_uri'=>redirect_uri,
        'state'=>state,'nonce'=>nonce,'code_challenge'=>challenge,'code_challenge_method'=>'S256'})
      uri.query = URI.encode_www_form(query)
      uri.to_s
    end
    def self.finish!(state:, code:, browser:, current_actor: nil)
      attempt = LoginAttempt.find_by!(state_digest: Digest::SHA256.hexdigest(state.to_s))
      attempt.with_lock do
        raise Invalid, 'Sign-in request expired or already used' if attempt.consumed_at || attempt.expires_at < Time.current
        raise Invalid, 'Sign-in browser mismatch' unless browser.present? && ActiveSupport::SecurityUtils.secure_compare(attempt.browser_digest,Digest::SHA256.hexdigest(browser))
        raise Invalid, 'Account-linking session changed' if attempt.user_id && attempt.user_id != current_actor&.id
        attempt.update!(consumed_at: Time.current)
      end
      connection = attempt.connection
      raise Invalid, 'Organization sign-in is disabled' unless connection.enabled?
      secrets = Sealed.open(attempt.secret_box, context: "oidc:#{attempt.state_digest}")
      credential = LightekVault::Service.checkout!(slug: slug(connection), consumer: name, purpose: 'organization_sso', requested_by: "employer:#{connection.employer_id}")
      tokens = PublicHttp.json(connection.token_endpoint, basic: [connection.client_id,credential.fetch('client_secret')],
        form: {'grant_type'=>'authorization_code','code'=>code.to_s,'redirect_uri'=>secrets.fetch('redirect_uri'),'code_verifier'=>secrets.fetch('verifier')})
      claims = validate!(connection: connection, token: tokens.fetch('id_token'), nonce: secrets.fetch('nonce'))
      subject = claims.fetch('sub')
      if attempt.user_id
        active_member!(connection, attempt.user)
        binding = Subject.find_or_initialize_by(connection: connection, user: attempt.user)
        raise Invalid, 'Unlink the old identity before changing its subject' if binding.persisted? && binding.subject != subject
        binding.update!(subject: subject)
        return [attempt.user, connection, true]
      end
      binding = Subject.find_by!(connection: connection, subject: subject)
      active_member!(connection, binding.user)
      [binding.user, connection, false]
    rescue JWT::DecodeError, KeyError, ActiveRecord::RecordNotFound, PublicHttp::Invalid, ActiveRecord::RecordNotUnique
      raise Invalid, 'Organization sign-in could not be verified; use your local sign-in to link the organization account first'
    ensure
      credential&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
    end
    def self.active_member!(connection, user)
      raise Invalid, 'Enable a local authenticator before using organization sign-in' unless Mfa.enabled?(user)
      access = LightekPeople::Access.new(actor: user, employer: connection.employer)
      access.require_active!
    rescue LightekPeople::Access::Denied
      raise Invalid, 'Organization membership is no longer active'
    end
    def self.validate!(connection:, token:, nonce:)
      raise Invalid, 'ID token too large' unless token.is_a?(String) && token.bytesize < 30_000
      _, header = JWT.decode(token,nil,false)
      raise Invalid, 'Unsupported signing algorithm' unless header['alg'] == 'RS256' && header['kid'].is_a?(String) && header['kid'].length <= 200
      keys = PublicHttp.json(connection.jwks_uri).fetch('keys')
      jwk = keys.find { |k| k['kid'] == header['kid'] && k['kty'] == 'RSA' && (!k['use'] || k['use'] == 'sig') && (!k['alg'] || k['alg'] == 'RS256') }
      raise Invalid, 'Unknown provider signing key' unless jwk
      key = JWT::JWK.import(jwk).public_key
      raise Invalid, 'Provider signing key is too small' if key.n.num_bits < 2048
      claims, = JWT.decode(token,key,true, algorithms: ['RS256'], verify_expiration: true, verify_not_before: true,
        verify_iss: true, iss: connection.issuer, verify_aud: true, aud: connection.client_id, required_claims: %w[iss aud exp iat sub nonce], leeway: 30)
      raise Invalid, 'Invalid ID token issue time' unless claims['iat'].is_a?(Integer) && claims['iat'] <= Time.current.to_i + 30 && claims['iat'] > 10.minutes.ago.to_i
      raise Invalid, 'Invalid ID token lifetime' unless claims['exp'].is_a?(Integer) && claims['exp'] > claims['iat']
      raise Invalid, 'Identity subject is invalid' unless claims['sub'].is_a?(String) && claims['sub'].bytesize.between?(1,255)
      audiences = Array(claims['aud'])
      raise Invalid, 'Untrusted token audience' unless audiences == [connection.client_id]
      raise Invalid, 'Authorized party mismatch' if (audiences.length > 1 || claims.key?('azp')) && claims['azp'] != connection.client_id
      raise Invalid, 'Identity nonce mismatch' unless claims['nonce'].is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(claims['nonce'],nonce)
      claims
    end
  end
end
