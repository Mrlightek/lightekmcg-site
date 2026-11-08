module Gatekeeper
  module Compute
    module Providers
      class LinodeAdapter < Provider
        include HttpSupport
        BASE = "https://api.linode.com/v4".freeze

        def regions = collection("/regions")
        def plans = collection("/linode/types", authenticated: false)
        def images = collection("/images")
        def nodes = collection("/linode/instances")
        def node(id) = request(:get, "/linode/instances/#{id}")

        def create_support_ticket(summary:, description:, linode_id:)
          request(:post, "/support/tickets", body: {
            summary: summary, description: description, linode_id: Integer(linode_id)
          })
        end

        def provision_node(label:, region:, plan:, image:, root_password: nil, authorized_keys: nil, **options)
          auth = {}
          auth[:root_pass] = root_password if root_password.present?
          auth[:authorized_keys] = Array(authorized_keys) if authorized_keys.present?
          raise ConfigurationError, "Linode provisioning requires root_password or authorized_keys" if auth.empty?

          request(:post, "/linode/instances", body: {
            label: label, region: region, type: plan, image: image
          }.merge(auth).merge(options.compact))
        end

        def events_for(id)
          response = request(:get, '/account/events?page_size=100', filters: {
            'entity.type'=>'linode', 'entity.id'=>Integer(id), '+order_by'=>'id', '+order'=>'desc'})
          Array(response.fetch('data'))
        end

        def resize_node(id, plan:)
          baseline = events_for(id).map { |event| event['id'].to_i }.max.to_i
          request(:post, "/linode/instances/#{Integer(id)}/resize", body: {type: plan, allow_auto_disk_resize: false})
          {'after_event_id'=>baseline, 'target_plan'=>plan, 'requested_at'=>Time.current.iso8601}
        end

        def reboot_node(id) = request(:post, "/linode/instances/#{id}/reboot", body: {})
        def shutdown_node(id) = request(:post, "/linode/instances/#{id}/shutdown", body: {})
        def start_node(id) = request(:post, "/linode/instances/#{id}/boot", body: {})

        def destroy_node(id)
          request(:delete, "/linode/instances/#{id}")
          true
        rescue HttpSupport::RequestError => error
          raise unless error.status == 404
          true
        end

        def set_reverse_dns(ip:, hostname:)
          request(:put, "/networking/ips/#{URI.encode_www_form_component(ip)}", body: { rdns: hostname })
        end

        def healthcheck
          data = request(:get, "/account")
          { ok: true, provider: provider.slug, account: data["company"].presence || data["email"].presence || "connected" }
        end

        private

        def token
          payload = vault_payload
          payload["token"] || payload["value"] || raise(ConfigurationError, "Linode Vault credential must contain token")
        end

        def request(method, path, body: nil, authenticated: true, filters: nil)
          headers = authenticated ? { "Authorization" => "Bearer #{token}" } : {}
          headers['X-Filter'] = JSON.generate(filters) if filters
          json_request(method:, url: "#{BASE}#{path}", headers:, body:)
        end

        def collection(path, authenticated: true)
          response = request(:get, path, authenticated: authenticated)
          response.is_a?(Hash) && response["data"].is_a?(Array) ? response["data"] : Array(response)
        end
      end
    end
  end
end
