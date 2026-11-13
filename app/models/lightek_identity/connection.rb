module LightekIdentity
  class Connection < ApplicationRecord
    self.table_name = 'lightek_identity_connections'
    belongs_to :employer, class_name: 'User'
    validates :employer_id, :slug, uniqueness: true
    validates :slug, format: {with: /\A[a-z0-9][a-z0-9-]{2,79}\z/}
    validates :client_id, presence: true, length: {maximum: 200}
    validates :issuer, :authorization_endpoint, :token_endpoint, :jwks_uri, presence: true
    validate do
      %w[issuer authorization_endpoint token_endpoint jwks_uri].each do |field|
        uri = URI.parse(public_send(field)) rescue nil
        errors.add(field, 'must be an HTTPS URL without credentials or fragments') unless uri && uri.scheme == 'https' && uri.host && !uri.userinfo && !uri.fragment
      end
    end
  end
end
