require 'securerandom'
require 'uri'
module LightekReservations
  module Federation
    class Issuer
      CONSUMER = name.freeze
      def self.connect_existing!(order:, actor:)
        raise ArgumentError, 'Only the platform super admin can connect an existing server' unless actor.role == 'super_admin'
        raise ArgumentError, 'Server is not ready' unless LightekCommerce::Installations.ready?(order)
        request = ProvisioningRequest.find(order.provisioning_request_id)
        merchant = request.owner
        node = request.gatekeeper_node
        domain = LightekCommerce::Installations.hostname(order)
        configuration = ensure!(order: order, merchant: merchant, domain: domain)
        installation = GatekeeperInstallation.find_by!(gatekeeper_node: node, domain: domain, component: 'lightek_app')
        raise ArgumentError, 'A registered native Rails runtime is required' unless installation.adapter == 'native_rails'
        secret = LightekVault::Service.checkout!(slug: configuration.fetch('credential_slug'), consumer: CONSUMER,
          purpose: 'reservation_federation', requested_by: actor.email_address)
        receipt = Gatekeeper::Fleet::Transport.run!(node: node, domain: domain, requested_by: actor.email_address,
          operation_id: nil, script_name: 'sync_federation.py', payload: {domain: domain, owner_email: merchant.email_address,
            connection: configuration.merge('token' => secret.fetch('token')), deployment: installation.deployment_config})
        raise ArgumentError, 'Connection receipt did not match the installation' unless receipt['status'] == 'connected' && receipt['key'] == configuration['key']
        receipt
      ensure
        secret&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
      end
      def self.origin
        value = ENV.fetch('LIGHTEK_RESERVATION_ORIGIN', 'https://lightekmcg.com')
        uri = URI.parse(value)
        raise ArgumentError, 'Central reservation origin must be an HTTPS origin' unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && uri.path.in?(['','/']) && !uri.query && !uri.fragment
        value.delete_suffix('/')
      end
      def self.ensure!(order:, merchant:, domain:)
        raise ArgumentError, 'A verified paid server order is required' unless order.paid_at? && %w[paid fulfilled].include?(order.status) && order.items.any? { |item| item.product.product_type == 'lightek_instance' }
        peer = nil
        order.with_lock do
          peer = Peer.find_by(order: order)
          unless peer
            site = DymondSite::Site.find_or_initialize_by(host: domain)
            raise ArgumentError, 'Reseller hostname belongs to another account' if site.persisted? && site.tenant != merchant
            site.assign_attributes(name: "#{merchant.first_name}'s server resort", tenant: merchant) if site.new_record?
            site.save!
            key = SecureRandom.uuid
            token = "#{key}.#{SecureRandom.hex(32)}"
            # Only the digest goes into peer records. The recoverable installation
            # credential remains in Vault and is never saved to deployment metadata.
            LightekVault::Service.store!(name: "Reservation peer #{key}", slug: "reservation-peer-#{key}",
              payload: {'token'=>token}, provider: 'lightek', purpose: 'reservation_federation',
              access_policy: {'consumers'=>[CONSUMER, 'Gatekeeper::WebsiteDeployment'], 'purposes'=>['reservation_federation']},
              requested_by: merchant.email_address)
            peer = Peer.create!(key: key, token_digest: Digest::SHA256.hexdigest(token), order: order, merchant: merchant, site: site)
          end
        end
        {'origin'=>origin, 'key'=>peer.key, 'credential_slug'=>"reservation-peer-#{peer.key}"}
      end
    end
  end
end
