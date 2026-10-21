# frozen_string_literal: true
require "digest"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

module NevaehIntelligences
  # A neutral, inert boundary between a proposed ticket implementation and
  # repository promotion. This is NOT a code-generating AI or execution grant.
  module GithubPatchBoundaryV7a
    class Rejected < StandardError; end
    module_function
    MAX_FILES = 12
    MAX_SOURCE_BYTES = 64 * 1024

    # Proposed sources can come from any independent code generation engine.
    # Ruby is syntax-checked, NEVER loaded, and NEVER executed by this boundary.
    def package(plan:, changes:, root:)
      raise Rejected, "test only" unless Rails.env.test?
      raise Rejected, "inert plan required" unless plan.is_a?(Hash) && plan["status"] == "planning_only" && plan["execution_enabled"] == false
      raise Rejected, "invalid plan policy" unless plan.dig("gatekeeper", "authorization_required") == true && plan.dig("gatekeeper", "production_execution_allowed") == false && plan.dig("gatekeeper", "human_release_approval_required") == true
      raise Rejected, "invalid plan identity" unless plan["tracking_key"].is_a?(String) && /\ASTUDIO-\d{3}\z/.match?(plan["tracking_key"]) && /\A[0-9a-f]{64}\z/.match?(plan["fingerprint"].to_s)
      raise Rejected, "changes must be a bounded hash" unless changes.is_a?(Hash) && changes.size.between?(1, MAX_FILES)
      raise Rejected, "isolated directory required" unless root.is_a?(String) && File.directory?(root) && !File.symlink?(root)
      home = File.realpath(root)
      repo = File.realpath(Rails.root.to_s)
      raise Rejected, "inside application" if home == repo || home.start_with?(repo + File::SEPARATOR)
      changes.each do |path, source|
        raise Rejected, "unsafe path" unless path.is_a?(String) && /\A(?:app\/services|test\/services)\/(?:[a-z0-9_]+\/)*[a-z0-9_]+\.rb\z/.match?(path)
        raise Rejected, "unsafe path component" if path.split("/").include?("..")
        raise Rejected, "existing tracked or untracked path cannot be replaced" if File.exist?(Rails.root.join(path)) || File.symlink?(Rails.root.join(path))
        raise Rejected, "bad source" unless source.is_a?(String) && source.valid_encoding? && source.bytesize.between?(1, MAX_SOURCE_BYTES) && !source.include?("\0")
      end
      folder = Dir.mktmpdir("nevaeh-7a7-patch-", home)
      begin
        evidence = []
        changes.each do |path, source|
          destination = File.join(folder, "files", path)
          FileUtils.mkdir_p(File.dirname(destination), mode: 0o700)
          File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(source) }
          stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-c", destination, unsetenv_others: false)
          raise Rejected, "Ruby syntax failed: #{path}" unless status.success? && stdout.include?("Syntax OK")
          evidence << { "path" => path, "sha256" => Digest::SHA256.hexdigest(source), "syntax_passed" => true, "syntax_output_sha256" => Digest::SHA256.hexdigest(stdout + stderr) }
        end
        manifest = { "schema_version" => 1, "status" => "syntax_verified_untrusted_proposal", "tracking_key" => plan.fetch("tracking_key"), "ticket_id" => plan.fetch("ticket_id"), "plan_sha256" => plan.fetch("fingerprint"), "files" => evidence, "execution_authorized" => false, "feature_complete" => false, "release_approved" => false, "tests_executed" => false }
        File.open(File.join(folder, "manifest.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(manifest) + "\n") }
        { "directory" => folder, "manifest" => manifest }
      rescue StandardError
        FileUtils.remove_entry(folder) if File.directory?(folder)
        raise
      end
    end
  end
end
