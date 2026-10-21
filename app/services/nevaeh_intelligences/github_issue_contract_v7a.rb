# frozen_string_literal: true

require "json"
require "digest"

module NevaehIntelligences
  # Pure-data, fail-closed translation of canonical Studio GitHub issues.
  # No API requests, ticket creation, dispatch or code execution occurs here.
  module GithubIssueContractV7a
    REPOSITORY = "Mrlightek/lightekmcg-site"
    ISSUE_PATTERN = %r{\Ahttps://github\.com/Mrlightek/lightekmcg-site/issues/([1-9]\d*)\z}
    KEY_PATTERN = /\A(?:STUDIO)-\d{3}\z/
    PRIORITIES = %w[P0 P1 P2 P3].freeze
    STATUSES = %w[todo in_progress done blocked].freeze

    class ContractError < StandardError; end

    module_function

    def from_issue(issue, roadmap:)
      issue = stringify_keys(issue)
      url = issue.fetch("html_url") { issue.fetch("url") }
      match = ISSUE_PATTERN.match(String(url))
      raise ContractError, "unexpected GitHub issue URL" unless match
      raise ContractError, "issue is a pull request" if issue.key?("pull_request")
      raise ContractError, "issue is not open" unless issue.fetch("state") == "open"

      title = issue.fetch("title").to_s
      title_match = /\A\[(STUDIO-\d{3})\]\s+(.+)\z/.match(title)
      raise ContractError, "title missing Studio key" unless title_match
      key = title_match[1]
      raise ContractError, "invalid key" unless KEY_PATTERN.match?(key)

      data = roadmap.is_a?(String) ? JSON.parse(roadmap) : roadmap
      raise ContractError, "roadmap is not a hash" unless data.is_a?(Hash)
      project = stringify_keys(data.fetch("project"))
      github = stringify_keys(project.fetch("tracking").fetch("github"))
      raise ContractError, "roadmap repository mismatch" unless github.fetch("repository") == REPOSITORY
      item = Array(data.fetch("items")).find { |entry| entry.is_a?(Hash) && entry["key"] == key }
      raise ContractError, "issue is not in canonical roadmap" unless item
      raise ContractError, "roadmap item already complete" if item["status"] == "done"
      raise ContractError, "roadmap issue title mismatch" unless item.fetch("title").strip == title_match[2].strip
      raise ContractError, "invalid priority" unless PRIORITIES.include?(item.fetch("priority"))
      raise ContractError, "invalid roadmap status" unless STATUSES.include?(item.fetch("status"))

      body = issue.fetch("body").to_s
      marker = /<!--\s*LIGHTEK_STUDIO_KEY:(STUDIO-\d{3})\s*-->/.match(body)
      raise ContractError, "issue body tracking marker mismatch" unless marker && marker[1] == key
      source_line = body.match(/^`config\/project_tracking\/lightek_studio\.json`$/)
      raise ContractError, "issue missing roadmap source reference" unless source_line

      summary = item.fetch("summary").to_s.strip
      raise ContractError, "roadmap item objective missing" if summary.empty?
      number = match[1].to_i
      raise ContractError, "issue number mismatch" if issue.key?("number") && issue["number"].to_i != number
      canonical = {
        "schema_version" => 1,
        "repository" => REPOSITORY,
        "source" => "github_issue",
        "source_url" => url,
        "source_number" => number,
        "tracking_key" => key,
        "title" => item.fetch("title"),
        "phase" => item.fetch("phase"),
        "area" => item.fetch("area"),
        "priority" => item.fetch("priority"),
        "effort" => Integer(item.fetch("effort")),
        "objective" => summary,
        "status" => item.fetch("status"),
        "requires_authorization" => true,
        "execution_enabled" => false
      }
      canonical["fingerprint"] = Digest::SHA256.hexdigest(JSON.generate(canonical))
      canonical.freeze
    rescue KeyError, ArgumentError, TypeError, JSON::ParserError => e
      raise ContractError, "invalid issue/roadmap contract: #{e.class}"
    end

    def stringify_keys(value)
      raise ContractError, "expected object" unless value.is_a?(Hash)
      value.transform_keys(&:to_s)
    end
  end
end
