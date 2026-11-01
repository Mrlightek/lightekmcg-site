# frozen_string_literal: true
require "net/http"
require "json"

module NevaehIntelligences
  class GithubIssueClient
    REPOSITORY = GithubIssueContractV7a::REPOSITORY
    class Error < StandardError; end

    def initialize(token: ENV["GITHUB_ACTIONS_TOKEN"], transport: nil)
      @token, @transport = token, transport
    end

    def issues(page: 1)
      data = request(:get, "/issues?state=open&sort=created&direction=asc&per_page=100&page=#{Integer(page)}")
      raise Error, "Unexpected GitHub issue listing" unless data.is_a?(Array)
      {"records" => data.reject { |row| row.key?("pull_request") }, "more" => data.length == 100}
    end

    def issue(number)
      request(:get, "/issues/#{Integer(number)}")
    end

    private

    def request(method, path, body = nil)
      return @transport.call(method, path, body) if @transport
      uri = URI("https://api.github.com/repos/#{REPOSITORY}#{path}")
      klass = method == :get ? Net::HTTP::Get : Net::HTTP::Patch
      req = klass.new(uri)
      req["Accept"] = "application/vnd.github+json"
      req["X-GitHub-Api-Version"] = "2022-11-28"
      req["User-Agent"] = "Lightek-Nevaeh"
      req["Authorization"] = "Bearer #{@token}" unless @token.to_s.empty?
      if body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(req) }
      raise Error, "GitHub request failed (HTTP #{res.code}); retry after checking repository access or rate limits" unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    rescue JSON::ParserError
      raise Error, "GitHub returned malformed JSON"
    end
  end
end
