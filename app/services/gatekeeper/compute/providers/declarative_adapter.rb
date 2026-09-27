module Gatekeeper
  module Compute
    module Providers
      class DeclarativeAdapter < Provider
        include HttpSupport

        def healthcheck
          mapping = provider.configuration.to_h["healthcheck"]
          return super unless mapping
          invoke!(mapping)
          { ok: true, provider: provider.slug, adapter: self.class.name }
        end

        def regions = mapped!("regions")
        def plans = mapped!("plans")
        def images = mapped!("images")
        def nodes = mapped!("nodes")
        def node(id) = mapped!("node", id:)
        def provision_node(**kwargs) = mapped!("provision_node", **kwargs)
        def reboot_node(id) = mapped!("reboot_node", id:)
        def shutdown_node(id) = mapped!("shutdown_node", id:)
        def start_node(id) = mapped!("start_node", id:)
        def destroy_node(id) = mapped!("destroy_node", id:)
        def set_reverse_dns(ip:, hostname:) = mapped!("set_reverse_dns", ip:, hostname:)

        private

        def mapped!(name, **params)
          mapping = provider.configuration.to_h.dig("endpoints", name)
          raise UnsupportedCapability, "#{provider.slug} has no mapping for #{name}" unless mapping
          invoke!(mapping, params:)
        end

        def invoke!(mapping, params: {})
          path = mapping.fetch("path").dup
          params.stringify_keys.each { |k, v| path.gsub!("{#{k}}", URI.encode_www_form_component(v.to_s)) }
          credentials = provider.credential_secret_slug.present? ? vault_payload : {}
          headers = mapping.fetch("headers", {}).transform_values do |value|
            value.to_s.gsub(/\{\{credential\.([a-zA-Z0-9_]+)\}\}/) { credentials.fetch(Regexp.last_match(1)) }
          end
          result = json_request(
            method: mapping.fetch("method", "GET").downcase.to_sym,
            url: "#{provider.api_base_url.to_s.delete_suffix('/')}#{path}",
            headers:,
            body: mapping["send_body"] ? params : mapping["body"]
          )
          key = mapping["collection_key"]
          key.present? && result.is_a?(Hash) ? result.fetch(key, []) : result
        end
      end
    end
  end
end
