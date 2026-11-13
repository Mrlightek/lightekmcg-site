require "digest"
module LightekCommerce
  class NetworkAccounts
    def self.resolve!(peer:, chain:, store_name:)
      raise ArgumentError, "Invalid merchant account chain" unless chain.is_a?(Array) && chain.size.between?(1, 64)
      raise ArgumentError, "Merchant root does not match this installation" unless chain.first.fetch("email").downcase == peer.merchant.email_address
      user, site = peer.merchant, peer.site
      chain.drop(1).each do |entry|
        subject = entry.fetch("subject")
        raise ArgumentError, "Invalid account subject" unless subject.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
        mapping = NetworkAccount.find_by(peer: peer, source_subject: subject)
        if mapping
          raise ArgumentError, "Account parent changed; an approved transfer is required" unless mapping.user.agency_id == user.id
          user, site = mapping.user, mapping.site
        else
          candidate = User.find_by(email_address: entry.fetch("email").strip.downcase)
          if candidate
            raise ArgumentError, "Existing account is outside this reseller branch" unless candidate.agency_id == user.id && candidate.role.in?(%w[client white_label])
          else
            candidate = User.create!(agency: user, email_address: entry.fetch("email"), first_name: entry["first_name"].presence || "Business",
              last_name: entry["last_name"].presence || "Owner", role: entry["role"] == "white_label" ? "white_label" : "client", password_setup_required: true, password: SecureRandom.urlsafe_base64(36))
          end
          host = "network-#{Digest::SHA256.hexdigest("#{peer.key}:#{subject}").first(24)}.lightekmcg.com"
          site = DymondSite::Site.create!(tenant: candidate, name: store_name.to_s.first(160), host: host, manifest: {"network_ledger" => true})
          NetworkAccount.create!(peer: peer, source_subject: subject, user: candidate, site: site)
          user = candidate
        end
        user.update!(upstream_share_bps: Integer(entry.fetch("upstream_share_bps", 0)))
      end
      [user, site]
    end
  end
end
