require "uri"
module Gatekeeper
  module Hosting
    class BuildSetup
      SETTINGS_SLUG = "gatekeeper-image-build-settings".freeze
      REGISTRY_SLUG = "gatekeeper-image-registry".freeze
      CONSUMER = name.freeze
      PURPOSE = "image_build_setup".freeze

      def self.settings(actor:)
        return {} unless LightekVault::Secret.active.exists?(slug: SETTINGS_SLUG)
        LightekVault::Service.checkout!(slug: SETTINGS_SLUG, consumer: CONSUMER, purpose: PURPOSE, requested_by: actor.email_address)
      end

      def self.checkout(slug, actor)
        secret = LightekVault::Secret.active.find_by!(slug: slug)
        secret.with_lock do
          policy = secret.access_policy.to_h.deep_dup
          %w[consumers purposes].each do |field|
            next if Array(policy[field]).empty?
            policy[field] |= [field == "consumers" ? CONSUMER : PURPOSE]
          end
          if policy != secret.access_policy
            secret.update!(access_policy: policy)
            LightekVault::Service.audit!(secret: secret, action: "image_build_policy_connected", requested_by: actor.email_address,
              allowed: true, reason: "super admin connected existing credential to image building")
          end
        end
        LightekVault::Service.checkout!(slug: slug, consumer: CONSUMER, purpose: PURPOSE, requested_by: actor.email_address)
      end

      def self.connection_slug(actor:, requested: nil)
        return requested if requested.present?
        configured = ENV["LIGHTEK_GITHUB_SECRET_SLUG"].presence
        return configured if configured
        previous = settings(actor: actor)["credential_slug"].presence
        return previous if previous
        candidates = LightekVault::Secret.active.where("LOWER(provider) = ?", "github").where.not(slug: [SETTINGS_SLUG, REGISTRY_SLUG]).pluck(:slug)
        return candidates.first if candidates.one?
        if ENV["GITHUB_ACTIONS_TOKEN"].present?
          slug = "gatekeeper-github-connection"
          LightekVault::Service.store!(name: "GitHub build connection", slug: slug, payload: {"token" => ENV.fetch("GITHUB_ACTIONS_TOKEN")},
            provider: "github", purpose: PURPOSE, access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]}, requested_by: actor.email_address)
          return slug
        end
        raise Access::Denied, "Connect an existing GitHub credential below. GitHub authorization is needed once; callback URLs and build configuration are automatic."
      end

      def self.callback_url(value)
        uri = URI.parse(value.to_s)
        raise Access::Denied, "Use this environment's publicly reachable HTTPS origin for image-build callbacks. GitHub cannot reach localhost." unless
          uri.is_a?(URI::HTTPS) && !uri.userinfo && !uri.query && !uri.fragment && ["", "/"].include?(uri.path) &&
          LightekSettings::SiteDomain.public_hostname?(uri.host)
        "https://#{uri.host}#{uri.port == 443 ? '' : ":#{uri.port}"}/gatekeeper/application-images"
      rescue URI::InvalidURIError
        raise Access::Denied, "Use a valid public HTTPS origin."
      end

      def self.prepare!(actor:, origin:, credential_slug: nil, dependency_slug: nil, registry_slug: nil)
        raise Access::Denied, "Super admin required" unless Access.super_admin?(actor)
        previous = settings(actor: actor)
        callback = callback_url(origin.presence || previous["origin"])
        slug = connection_slug(actor: actor, requested: credential_slug)
        client = GithubClient.new(checkout(slug, actor))
        repository = client.call(:get, "/repos/#{ImageBuilds::REPOSITORY}")
        dependency_slug = dependency_slug.presence || previous["dependency_slug"]
        synchronize_dependencies!(client: client, actor: actor, dependency_slug: dependency_slug, connection_slug: slug)
        prepare_registry!(client: client, actor: actor, connection_slug: slug, selected_slug: registry_slug)
        config = {"credential_slug" => slug, "dependency_slug" => dependency_slug,
          "origin" => callback.delete_suffix("/gatekeeper/application-images"), "callback_url" => callback,
          "repository_id" => repository.fetch("id").to_s}
        LightekVault::Service.store!(name: "Application image build settings", slug: SETTINGS_SLUG, payload: config,
          provider: "lightek", purpose: PURPOSE, access_policy: {"consumers" => [CONSUMER], "purposes" => [PURPOSE]}, requested_by: actor.email_address)
        config
      ensure
        client&.close
      end

      def self.synchronize_dependencies!(client:, actor:, dependency_slug:, connection_slug:)
        names = []
        page = 1
        loop do
          rows = client.call(:get, "/repos/#{ImageBuilds::REPOSITORY}/actions/secrets?per_page=100&page=#{page}").fetch("secrets")
          names.concat(rows.map { |row| row.fetch("name") })
          break if rows.size < 100
          page += 1
        end
        app_id_variable = client.call(:get, "/repos/#{ImageBuilds::REPOSITORY}/actions/variables/LIGHTEK_CI_APP_ID", missing: true)
        return if names.include?("LIGHTEK_CI_APP_PRIVATE_KEY") && (names.include?("LIGHTEK_CI_APP_ID") || app_id_variable)
        payload = checkout(dependency_slug.presence || connection_slug, actor)
        raise Access::Denied, "Connect the existing CI GitHub App credential (app_id and private_key) below so Lightek can configure private dependency access automatically." if payload["app_id"].blank? || payload["private_key"].blank?
        unless names.include?("LIGHTEK_CI_APP_ID") || app_id_variable
          client.call(:post, "/repos/#{ImageBuilds::REPOSITORY}/actions/variables", body: {name: "LIGHTEK_CI_APP_ID", value: payload.fetch("app_id").to_s})
        end
        unless names.include?("LIGHTEK_CI_APP_PRIVATE_KEY")
          public_key = client.call(:get, "/repos/#{ImageBuilds::REPOSITORY}/actions/secrets/public-key")
          encrypted = GithubSecretBox.encrypt(payload.fetch("private_key"), public_key.fetch("key"))
          client.call(:put, "/repos/#{ImageBuilds::REPOSITORY}/actions/secrets/LIGHTEK_CI_APP_PRIVATE_KEY",
            body: {encrypted_value: encrypted, key_id: public_key.fetch("key_id")})
        end
      ensure
        payload&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      end

      def self.registry_slug
        ENV["LIGHTEK_FLEET_REGISTRY_SECRET_SLUG"].presence || (REGISTRY_SLUG if LightekVault::Secret.active.exists?(slug: REGISTRY_SLUG))
      end

      def self.prepare_registry!(client:, actor:, connection_slug:, selected_slug: nil)
        return if registry_slug && selected_slug.blank?
        payload = checkout(selected_slug.presence || connection_slug, actor)
        token = payload["password"].presence || payload["registry_token"].presence || (payload["token"].presence || payload["value"].presence unless payload["app_id"].present?)
        raise Access::Denied, "Connect an existing registry credential below. Private GHCR images need a credential authorized to read packages." if token.blank? || (token.start_with?("github_pat_") && payload["registry_token"].blank? && payload["password"].blank?)
        username = payload["username"].presence || client.call(:get, "/user").fetch("login")
        LightekVault::Service.store!(name: "Application image registry", slug: REGISTRY_SLUG,
          payload: {"username" => username, "password" => token}, provider: "github", purpose: "fleet_registry",
          access_policy: {"consumers" => ["Gatekeeper::Fleet::Transport"], "purposes" => ["fleet_registry"]}, requested_by: actor.email_address)
      ensure
        payload&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
      end

      def self.client(actor:)
        config = settings(actor: actor)
        GithubClient.new(checkout(config.fetch("credential_slug"), actor))
      end
    end
  end
end
