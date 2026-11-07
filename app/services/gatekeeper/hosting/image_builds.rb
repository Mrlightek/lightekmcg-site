require "net/http"
require "json"
module Gatekeeper
  module Hosting
    class ImageBuilds
      REPOSITORY = "Mrlightek/lightekmcg-site".freeze
      def self.queue!(actor:, attributes:)
        raise Access::Denied, "Super admin required" unless Access.super_admin?(actor)
        ref = attributes.fetch("source_ref").to_s
        raise Access::Denied, "Choose a branch or commit without spaces" unless ref.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._\/-]{0,199}\z/) && !ref.include?("..")
        token = ENV["GITHUB_ACTIONS_TOKEN"].presence || raise(Access::Denied, "Configure GITHUB_ACTIONS_TOKEN to build images from Dashboard")
        template = GatekeeperApplicationTemplate.create!(name: attributes.fetch("name"), preview_domain: attributes["preview_domain"],
          kind: "docker", build_status: "queued", source_ref: ref, enabled: false, rails_database: true, rails_worker: true,
          credential_slug: attributes["credential_slug"], container_port: 3000)
        uri = URI("https://api.github.com/repos/#{REPOSITORY}/actions/workflows/application-image.yml/dispatches")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Accept"] = "application/vnd.github+json"
        request["Content-Type"] = "application/json"
        request["X-GitHub-Api-Version"] = "2022-11-28"
        request.body = JSON.generate(ref: ref, inputs: {template_id: template.id.to_s})
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
        raise Access::Denied, "Image build dispatch failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
        template
      rescue StandardError
        template&.update!(build_status: "failed", enabled: false)
        raise
      end
    end
  end
end
