# frozen_string_literal: true

require "open3"
require "tmpdir"

module ReleaseAssurance
  class BrowserJob < ApplicationJob
    queue_as :release_assurance

    def perform(environment_id)
      Policy.runner!
      environment = Environment.find(environment_id)
      return unless environment.active?

      candidate = environment.candidate
      Policy.authorize!(candidate.operator, candidate)
      hostname = Policy.hostname!(environment.hostname)
      Dir.mktmpdir("release-browser-") do |dir|
        screenshot = File.join(dir, "homepage.png")
        stdout, stderr, status = Open3.capture3("node", Rails.root.join("script/lightek/release_assurance_browser.cjs").to_s,
          hostname, candidate.source_sha, screenshot)
        candidate.with_lock do
          return unless environment.reload.active?

          run = candidate.runs.create!(environment: environment, check_key: "browser_smoke", kind: "automated",
            result: status.success? ? "passed" : "failed", source_sha: candidate.source_sha,
            evidence: { "summary" => status.success? ? stdout.strip : stderr.strip })
          Feedback.attach_png!(run, File.binread(screenshot)) if status.success?
        end
      end
      Nevaeh.review!(candidate, candidate.operator)
    rescue Errno::ENOENT, Policy::Denied => error
      Rails.logger.warn("[Release Assurance] browser=#{environment_id} error=#{error.class.name}")
    end
  end
end
