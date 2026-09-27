module Gatekeeper
  module Compute
    module Providers
      class OvhAdapter < Provider
        include HttpSupport

        ENDPOINTS = {
          "ovh-eu" => "https://eu.api.ovh.com/1.0",
          "ovh-ca" => "https://ca.api.ovh.com/1.0",
          "ovh-us" => "https://api.us.ovhcloud.com/1.0"
        }.freeze

        def healthcheck
          data = ovh_request(:get, "/me")
          { ok: true, provider: provider.slug, account: data["nichandle"].presence || data["email"].presence || "connected" }
        end

        %w[regions plans images nodes provision_node reboot_node shutdown_node start_node destroy_node set_reverse_dns].each do |name|
          define_method(name) do |*args, **kwargs|
            mapped_call!(name, args:, kwargs:)
          end
        end

        private

        def credentials
          @credentials ||= begin
            payload = vault_payload
            creds = {
              application_key: payload["application_key"],
              application_secret: payload["application_secret"],
              consumer_key: payload["consumer_key"]
            }
            missing = creds.select { |_k, v| v.blank? }.keys
            raise ConfigurationError, "OVH Vault credential missing #{missing.join(', ')}" if missing.any?
            creds
          end
        end

        def base_url
          endpoint = provider.configuration.to_h["endpoint"].presence || "ovh-us"
          provider.api_base_url.presence || ENDPOINTS.fetch(endpoint)
        end

        def ovh_request(method, path, body: nil)
          creds = credentials
          body_json = body ? JSON.generate(body) : ""
          timestamp = Time.now.to_i
          url = "#{base_url}#{path}"
          material = [creds[:application_secret], creds[:consumer_key], method.to_s.upcase, url, body_json, timestamp].join("+")
          signature = "$1$#{Digest::SHA1.hexdigest(material)}"
          headers = {
            "X-Ovh-Application" => creds[:application_key],
            "X-Ovh-Consumer" => creds[:consumer_key],
            "X-Ovh-Timestamp" => timestamp.to_s,
            "X-Ovh-Signature" => signature
          }
          json_request(method:, url:, headers:, body:)
        end

        def mapped_call!(capability, args: [], kwargs: {})
          mapping = provider.configuration.to_h.dig("endpoints", capability)
          raise UnsupportedCapability, "OVH capability #{capability} has no endpoint mapping" unless mapping

          params = kwargs.stringify_keys
          args.each_with_index { |value, i| params["arg#{i + 1}"] = value }
          path = mapping.fetch("path").dup
          params.each { |key, value| path.gsub!("{#{key}}", URI.encode_www_form_component(value.to_s)) }
          service_name = provider.configuration.to_h["service_name"]
          path.gsub!("{service_name}", URI.encode_www_form_component(service_name.to_s)) if service_name.present?
          result = ovh_request(mapping.fetch("method", "GET").downcase.to_sym, path, body: mapping["send_body"] ? kwargs : mapping["body"])
          key = mapping["collection_key"]
          key.present? && result.is_a?(Hash) ? result.fetch(key, []) : result
        end
      end
    end
  end
end
