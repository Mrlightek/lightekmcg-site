require "uri"
require "ipaddr"
module Gatekeeper
  module Fleet
    module Adapters
      NAMES = %w[native_rails cdn_nginx systemd_service docker_compose].freeze
      MAIN_REPOSITORY = "https://github.com/Mrlightek/lightekmcg-site.git"
      PATH_KEYS = %w[app_root env_file ruby_bin compose_file backup_hook deploy_hook verify_hook maintenance_hook config_file].freeze
      KEYS = (PATH_KEYS + %w[app_user health_url revision_url probe_address worker_mode worker_service cable_service compose_project db_service service_name service_action backup_strategy]).freeze

      def self.repository_key(value)
        value.to_s.sub(/\Agit@([^:]+):/, 'https://\1/').delete_suffix(".git").downcase
      end

      def self.repository?(value)
        value.to_s.match?(%r{\A(?:https://[a-zA-Z0-9.-]+/|git@[a-zA-Z0-9.-]+:)[a-zA-Z0-9_.-]+/[a-zA-Z0-9_./-]+\z}) && !value.to_s.split("/").include?("..")
      end

      def self.validate!(adapter, config)
        raise ArgumentError, "Unknown deployment adapter" unless NAMES.include?(adapter)
        raise ArgumentError, "Deployment configuration must be an object" unless config.is_a?(Hash)
        raise ArgumentError, "Unsupported deployment configuration fields" unless (config.keys - KEYS).empty?
        config.each do |key, value|
          raise ArgumentError, "Configuration values must be strings" unless value.is_a?(String) && !value.match?(/[\x00-\x1f]/)
          next if value.empty?
          if key == "probe_address"
            IPAddr.new(value)
          elsif PATH_KEYS.include?(key)
            raise ArgumentError, "#{key} must be an absolute path without parent traversal" unless value.start_with?("/") && !value.split("/").include?("..")
          elsif %w[health_url revision_url].include?(key)
            uri = URI.parse(value)
            raise ArgumentError, "#{key} must be HTTPS without credentials" unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && !uri.fragment
          elsif %w[app_user worker_service cable_service compose_project db_service service_name].include?(key)
            raise ArgumentError, "Invalid #{key}" unless value.match?(/\A[a-zA-Z0-9_][a-zA-Z0-9_.@-]*\z/)
          end
        end
        return true if adapter == "docker_compose"
        required = %w[app_root app_user health_url]
        required += %w[env_file ruby_bin revision_url] if adapter == "native_rails"
        required += %w[config_file service_name] if adapter == "cdn_nginx"
        required += %w[service_name] if adapter == "systemd_service"
        raise ArgumentError, "Missing #{(required.select { |key| config[key].blank? }).join(', ')}" if required.any? { |key| config[key].blank? }
        if adapter == "native_rails"
          raise ArgumentError, "Choose a supported worker mode" unless %w[systemd compose none].include?(config.fetch("worker_mode", "systemd"))
          raise ArgumentError, "A worker service is required" if config.fetch("worker_mode", "systemd") != "none" && config["worker_service"].blank?
          strategy = config.fetch("backup_strategy", "compose")
          raise ArgumentError, "Choose compose or hook database backup" unless %w[compose hook].include?(strategy)
          raise ArgumentError, "A backup hook is required" if strategy == "hook" && config["backup_hook"].blank?
        end
        if adapter == "systemd_service"
          raise ArgumentError, "Service requires a running revision URL or verification hook" if config["revision_url"].blank? && config["verify_hook"].blank?
          raise ArgumentError, "Choose restart or reload" unless %w[restart reload].include?(config.fetch("service_action", "restart"))
        end
        true
      rescue URI::InvalidURIError, IPAddr::InvalidAddressError
        raise ArgumentError, "Invalid deployment URL"
      end

      def self.payload(installation, release)
        validate!(installation.adapter, installation.deployment_config)
        %w[health_url revision_url].each do |key|
          url = installation.deployment_config[key]
          raise ArgumentError, "Health probes must belong to the registered installation hostname" if url.present? && URI.parse(url).host != installation.domain
        end
        {adapter: installation.adapter, component: installation.component, repository: release.repository,
          deployment: installation.deployment_config}
      end

      def self.script(adapter)
        adapter == "docker_compose" ? "update_installation.py" : "update_native_installation.py"
      end
    end
  end
end
