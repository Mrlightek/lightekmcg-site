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
      checks = Readiness::CI
      checks = checks.except(*Readiness::SIMULATED_CI) unless @candidate.profile == "msp"
      checks.each do |key, (path, required_jobs)|
        payload = request("actions/workflows/#{File.basename(path)}/runs",
          head_sha: @candidate.source_sha, branch: @candidate.publication_ref, per_page: MAX_RUNS)
        matching = payload.fetch("workflow_runs").select do |run|
          run["path"] == path && run["head_sha"] == @candidate.source_sha &&
            run["head_branch"] == @candidate.publication_ref && run["head_repository"]&.fetch("full_name", nil)&.casecmp?(REPOSITORY) &&
            %w[push workflow_dispatch].include?(run["event"])
        end
        run = matching.max_by { |entry| entry.fetch("id") }
        if run.nil?
          raise Unavailable, "Required GitHub Actions run is missing for #{key}" if require_current

          next
        end

        jobs = if run["status"] == "completed"
          request("actions/runs/#{Integer(run.fetch('id'))}/attempts/#{Integer(run.fetch('run_attempt'))}/jobs", per_page: 100).fetch("jobs")
        else
          []
        end
        result = result_for(run, jobs, required_jobs)
        @candidate.with_lock do
          receipt = @candidate.runs.find_or_initialize_by(check_key: key,
            external_id: "github:#{run.fetch('id')}:#{run.fetch('run_attempt')}")
          receipt.update!(source_sha: @candidate.source_sha, kind: Readiness::SIMULATED_CI.include?(key) ? "simulated" : "automated",
            result: result, evidence: { "run_id" => run.fetch("id"), "attempt" => run.fetch("run_attempt"), "workflow" => path })
        end
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
