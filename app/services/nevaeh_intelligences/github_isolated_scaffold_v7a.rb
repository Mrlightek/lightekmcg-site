# frozen_string_literal: true
require "json"
require "digest"
require "tmpdir"
require "fileutils"
require "ripper"

module NevaehIntelligences
  # Phase 7A.5: isolated, deterministic scaffold proof only. Never executes code,
  # checks out Git branches, invokes Bundler/Rails generators, or dispatches jobs.
  module GithubIsolatedScaffoldV7a
    class Rejected < StandardError; end
    module_function

    def build_from_ticket(ticket:, root:)
      raise Rejected, "test environment only" unless Rails.env.test?
      raise Rejected, "invalid artifact root" unless root.is_a?(String) && File.directory?(root) && !File.symlink?(root)
      real_root = File.realpath(root)
      raise Rejected, "artifact root inside application" if real_root == Rails.root.to_s || real_root.start_with?(Rails.root.to_s + File::SEPARATOR)
      plan = GithubDevelopmentPlanV7a.from_ticket(ticket: ticket)
      raise Rejected, "non-inert plan" unless plan["status"] == "planning_only" && plan["execution_enabled"] == false && plan.dig("gatekeeper", "production_execution_allowed") == false
      key = plan.fetch("tracking_key")
      raise Rejected, "invalid tracking key" unless /\ASTUDIO-[0-9]{3}\z/.match?(key)
      # No interpretation of issue content as executable Ruby. A fixed adapter
      # scaffold deliberately cannot perform requested feature implementation.
      class_name = "Studio#{key.delete('-')}Capability"
      source = <<~CODE
        # frozen_string_literal: true
        # Generated scaffold for #{key}; human/reasoning implementation pending.
        module NevaehGenerated
          class #{class_name}
            def self.call(*_args)
              raise NotImplementedError, "Capability implementation has not been generated or approved"
            end
          end
        end
      CODE
      raise Rejected, "invalid scaffold Ruby" unless Ripper.sexp(source)
      manifest = {
        "schema_version" => 1, "state" => "scaffold_only_not_implemented",
        "ticket_id" => plan.fetch("ticket_id"), "tracking_key" => key,
        "plan_fingerprint" => plan.fetch("fingerprint"),
        "source_sha256" => Digest::SHA256.hexdigest(source),
        "authorization" => "not_granted", "release_approved" => false,
        "feature_complete" => false, "tests_executed" => false
      }
      # Creating a fresh one-off directory refuses accidental replacement.
      directory = Dir.mktmpdir("nevaeh-7a5-#{key.downcase}-", real_root)
      begin
        File.write(File.join(directory, "scaffold.rb"), source, mode: "wx", perm: 0o600)
        File.write(File.join(directory, "manifest.json"), JSON.pretty_generate(manifest) + "\n", mode: "wx", perm: 0o600)
      rescue StandardError
        FileUtils.remove_entry(directory) if File.directory?(directory)
        raise
      end
      { "directory" => directory, "manifest" => manifest }
    end
  end
end
