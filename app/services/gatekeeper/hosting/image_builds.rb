require "securerandom"
module Gatekeeper
  module Hosting
    class ImageBuilds
      REPOSITORY = "Mrlightek/lightekmcg-site".freeze
      def self.queue!(actor:, attributes:, origin: nil)
        raise Access::Denied, "Super admin required" unless Access.super_admin?(actor)
        ref = attributes.fetch("source_ref").to_s
        raise Access::Denied, "Choose a branch or tag without spaces" unless ref.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._\/-]{0,199}\z/) && !ref.include?("..")
        raise Access::Denied, "Choose a named branch or tag for GitHub Actions." if ref.match?(/\A[0-9a-f]{40}\z/)
        config = BuildSetup.prepare!(actor: actor, origin: origin)
        client = BuildSetup.client(actor: actor)
        commit = client.call(:get, "/repos/#{REPOSITORY}/commits/#{URI.encode_www_form_component(ref)}")
        sha = commit.fetch("sha")
        raise Access::Denied, "GitHub did not return a source commit" unless sha.match?(/\A[0-9a-f]{40}\z/)
        template = GatekeeperApplicationTemplate.create!(name: attributes.fetch("name"), preview_domain: attributes["preview_domain"],
          kind: "docker", lightek_application: true, build_status: "queued", source_ref: ref, enabled: false, rails_database: true, rails_worker: true,
          credential_slug: attributes["credential_slug"], container_port: 3000)
        identity = {"source_sha" => sha, "repository_id" => config.fetch("repository_id"),
          "audience" => "#{config.fetch('callback_url')}/#{template.id}/#{SecureRandom.hex(16)}"}
        template.update!(build_identity: identity)
        client.call(:post, "/repos/#{REPOSITORY}/actions/workflows/customer-release.yml/dispatches",
          body: {ref: ref, inputs: {template_id: template.id.to_s, callback_url: config.fetch("callback_url"), callback_audience: identity.fetch("audience")}})
        template
      rescue StandardError
        template&.update!(build_status: "failed", enabled: false)
        raise
      ensure
        client&.close
      end
    end
  end
end
