# frozen_string_literal: true

require "open3"
require "tmpdir"

module ReleaseAssurance
  module BrowserSmoke
    def self.capture(environment, source_sha)
      hostname = Policy.hostname!(environment.hostname)
      Dir.mktmpdir("release-browser-") do |dir|
        screenshot = File.join(dir, "homepage.png")
        _, _, status = Open3.capture3("timeout", "--kill-after=5s", "90s", "node",
          Rails.root.join("script/lightek/release_assurance_browser.cjs").to_s, hostname, source_sha, screenshot)
        if status.success?
          yield "passed", "Staging HTTPS, revision, homepage and sign-in form verified.", screenshot
        else
          yield "failed", "Staging Chromium acceptance did not pass.", nil
        end
      end
    end

    def self.record!(environment, result, summary, screenshot, external_id: nil)
      candidate = environment.candidate
      run = candidate.runs.create!(environment: environment, check_key: "browser_smoke", kind: "automated",
        result: result, source_sha: candidate.source_sha, evidence: { "summary" => summary }, external_id: external_id)
      Feedback.attach_png!(run, File.binread(screenshot)) if screenshot
    end
  end
end
