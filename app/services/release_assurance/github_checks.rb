# frozen_string_literal: true

require "net/http"

module ReleaseAssurance
  class GithubChecks
    class Unavailable < StandardError; end

    REPOSITORY = "Mrlightek/lightekmcg-site"
    MAX_RUNS = 30

    def initialize(candidate)
      @candidate = candidate
    end

    def sync!(require_current: false)
      revision = @candidate.source_sha
      receipts = collect
      raise Unavailable, "A required GitHub Actions run is missing" if require_current && receipts.any?(&:nil?)

      @candidate.with_lock do
        raise Unavailable, "The published candidate revision changed" unless @candidate.source_sha == revision

        record!(receipts)
      end
    end

    def collect
      checks = Readiness::CI
      checks = checks.except(*Readiness::SIMULATED_CI) unless @candidate.profile == "msp"
      checks.map do |key, (path, required_jobs)|
        payload = request("actions/workflows/#{File.basename(path)}/runs",
          head_sha: @candidate.source_sha, branch: @candidate.publication_ref, per_page: MAX_RUNS)
        matching = payload.fetch("workflow_runs").select do |run|
          run["path"] == path && run["head_sha"] == @candidate.source_sha &&
            run["head_branch"] == @candidate.publication_ref && run["head_repository"]&.fetch("full_name", nil)&.casecmp?(REPOSITORY) &&
            %w[push workflow_dispatch].include?(run["event"])
        end
        run = matching.max_by { |entry| entry.fetch("id") }
        next if run.nil?

        jobs = if run["status"] == "completed"
          request("actions/runs/#{Integer(run.fetch('id'))}/attempts/#{Integer(run.fetch('run_attempt'))}/jobs", per_page: 100).fetch("jobs")
        else
          []
        end
        [key, result_for(run, jobs, required_jobs),
          { "run_id" => run.fetch("id"), "attempt" => run.fetch("run_attempt"), "workflow" => path }]
      end
    end

    # Call with the candidate locked. An older observation may finish after a newer poll.
    def record!(receipts)
      receipts.compact.each do |key, result, evidence|
        run_id, attempt = evidence.values_at("run_id", "attempt")
        recent = @candidate.runs.where(check_key: key, source_sha: @candidate.source_sha).where.not(external_id: nil).order(id: :desc).first
        if recent && recent.evidence.key?("run_id")
          comparison = [run_id, attempt] <=> recent.evidence.values_at("run_id", "attempt")
          next if comparison.negative? || (comparison.zero? && result == "running" && recent.result != "running")
        end

        receipt = @candidate.runs.find_or_initialize_by(check_key: key, external_id: "github:#{run_id}:#{attempt}")
        receipt.update!(source_sha: @candidate.source_sha, kind: Readiness::SIMULATED_CI.include?(key) ? "simulated" : "automated",
          result: result, evidence: evidence)
      end
    end

    private

    def result_for(run, jobs, required_jobs)
      return "running" unless run["status"] == "completed"
      return "failed" if %w[failure timed_out action_required].include?(run["conclusion"])
      return "blocked" unless run["conclusion"] == "success" &&
        required_jobs.all? { |name| jobs.any? { |job| job["name"] == name && job["conclusion"] == "success" } }

      "passed"
    end

    def request(path, **query)
      uri = URI("https://api.github.com/repos/#{REPOSITORY}/#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      headers = { "Accept" => "application/vnd.github+json", "User-Agent" => "Lightek-Release-Assurance",
        "X-GitHub-Api-Version" => "2022-11-28" }
      token = ENV["LIGHTEK_RELEASE_ASSURANCE_ACTIONS_TOKEN"]
      headers["Authorization"] = "Bearer #{token}" if token.present?
      message = Net::HTTP::Get.new(uri, headers)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(message)
      end
      raise Unavailable, "GitHub Actions returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      response.body.present? ? JSON.parse(response.body) : {}
    end
  end
end
