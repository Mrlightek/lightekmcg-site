# frozen_string_literal: true

require "net/http"

module ReleaseAssurance
  class ProductionPromotion
    CONSUMER = name
    PURPOSE = "production_promotion_verification"

    def self.authenticate!(authorization, revision)
      Policy.runner!
      slug = ENV.fetch("LIGHTEK_RELEASE_PROMOTION_VAULT_SLUG", "")
      raise Policy::Denied unless slug.present? && revision.match?(Source::SHA)

      payload = LightekVault::Service.checkout!(slug: slug, consumer: CONSUMER, purpose: PURPOSE,
        requested_by: "github-actions:#{revision}")
      expected = payload.fetch("token").to_s
      supplied = authorization.to_s
      raise Policy::Denied unless expected.bytesize >= 32 &&
        ActiveSupport::SecurityUtils.secure_compare("Bearer #{expected}", supplied)
    rescue LightekVault::Service::AccessDenied, KeyError, ActiveRecord::RecordNotFound
      raise Policy::Denied
    ensure
      expected.clear if expected && !expected.frozen?
    end

    def self.verify!(candidate, revision:, tree:, profile:)
      raise Policy::Denied unless revision.match?(Source::SHA) && tree.match?(Source::SHA) &&
        candidate.profile == profile && candidate.source_sha&.match?(Source::SHA)
      raise Policy::Denied unless github_sha("git/ref/heads/main").dig("object", "sha") == revision

      production_tree = github_sha("git/commits/#{revision}").dig("tree", "sha")
      tested_tree = github_sha("git/commits/#{candidate.source_sha}").dig("tree", "sha")
      raise Policy::Denied unless tree == production_tree && tree == tested_tree

      refresh_ci!(candidate)
      decision = Readiness.new(candidate).authorize_promotion!(candidate.operator, source_sha: candidate.source_sha)
      { candidate_id: candidate.id, source_sha: candidate.source_sha, production_sha: revision,
        tree_sha: tree, evidence_digest: decision.fetch(:digest) }
    rescue GithubChecks::Unavailable
      raise Policy::Denied
    end

    def self.refresh_ci!(candidate)
      GithubChecks.new(candidate).sync!(require_current: true)
    end
    private_class_method :refresh_ci!

    def self.github_sha(path)
      uri = URI("https://api.github.com/repos/#{GithubChecks::REPOSITORY}/#{path}")
      request = Net::HTTP::Get.new(uri, "Accept" => "application/vnd.github+json",
        "User-Agent" => "Lightek-Release-Assurance")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 6) do |http|
        http.request(request)
      end
      raise Policy::Denied unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError, IOError, SystemCallError, SocketError, Net::OpenTimeout, Net::ReadTimeout
      raise Policy::Denied
    end
    private_class_method :github_sha
  end
end
