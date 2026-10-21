# frozen_string_literal: true
require "json"
require "digest"
require "tmpdir"
require "fileutils"
require "open3"

module NevaehIntelligences
  # 7A.6: deliberately narrow, allowlisted STUDIO-203 executable feature slice.
  # Generates standalone capability-registry code AND tests from canonical roadmap
  # metadata. It cannot run arbitrary issue text or modify the Rails repository.
  module GithubRegistrySliceV7a
    class Rejected < StandardError; end
    module_function

    REGISTRY_SOURCE = <<~'CODE'.freeze
      # frozen_string_literal: true
      require "json"
      module NevaehGenerated
        module StudioCapabilityRegistry
          module_function
          def lookup(key, entries:)
            return nil unless key.is_a?(String) && /\ASTUDIO-\d{3}\z/.match?(key)
            record = entries.find { |item| item.is_a?(Hash) && item["key"] == key }
            return nil unless record
            { "key" => record.fetch("key"), "title" => record.fetch("title"),
              "status" => record.fetch("status"), "priority" => record.fetch("priority") }
          end
          def available(entries:)
            entries.filter_map { |item| lookup(item["key"], entries: entries) if item.is_a?(Hash) }
          end
        end
      end
    CODE

    TEST_SOURCE = <<~'CODE'.freeze
      # frozen_string_literal: true
      require "minitest/autorun"
      require "json"
      require_relative "registry"
      class GeneratedRegistryTest < Minitest::Test
        def entries
          JSON.parse(File.read(File.join(__dir__, "roadmap_slice.json"))).fetch("items")
        end
        def test_lookup_returns_real_ticket_metadata
          row = NevaehGenerated::StudioCapabilityRegistry.lookup("STUDIO-203", entries: entries)
          assert_equal "STUDIO-203", row.fetch("key")
          assert_equal "P0", row.fetch("priority")
        end
        def test_missing_and_injected_keys_are_rejected
          assert_nil NevaehGenerated::StudioCapabilityRegistry.lookup("STUDIO-999", entries: entries)
          assert_nil NevaehGenerated::StudioCapabilityRegistry.lookup("STUDIO-203; system('false')", entries: entries)
        end
        def test_available_is_pure_and_ordered
          before = Marshal.dump(entries)
          rows = NevaehGenerated::StudioCapabilityRegistry.available(entries: entries)
          assert_equal ["STUDIO-203"], rows.map { |r| r.fetch("key") }
          assert_equal before, Marshal.dump(entries)
        end
      end
    CODE

    def build_from_ticket(ticket:, root:)
      raise Rejected, "test environment only" unless Rails.env.test?
      raise Rejected, "outside artifact directory required" unless root.is_a?(String) && File.directory?(root) && !File.symlink?(root)
      dest = File.realpath(root)
      app = File.realpath(Rails.root.to_s)
      raise Rejected, "artifact root inside application" if dest == app || dest.start_with?(app + File::SEPARATOR)
      plan = GithubDevelopmentPlanV7a.from_ticket(ticket: ticket)
      raise Rejected, "unsupported issue" unless plan["tracking_key"] == "STUDIO-203" && plan["status"] == "planning_only"
      raise Rejected, "execution policy" unless plan["execution_enabled"] == false && plan.dig("gatekeeper", "production_execution_allowed") == false
      path = Rails.root.join("config/project_tracking/lightek_studio.json")
      raise Rejected, "roadmap symlink" if File.symlink?(path)
      roadmap_bytes = File.binread(path)
      roadmap = JSON.parse(roadmap_bytes)
      item = roadmap.fetch("items").find { |i| i["key"] == "STUDIO-203" }
      raise Rejected, "canonical issue missing" unless item && item["title"] == plan["requested_feature"]
      slice = { "schema_version" => 1, "items" => [item.slice("key", "title", "status", "priority")] }
      files = { "registry.rb" => REGISTRY_SOURCE, "registry_test.rb" => TEST_SOURCE,
                "roadmap_slice.json" => JSON.pretty_generate(slice) + "\n" }
      folder = Dir.mktmpdir("nevaeh-7a6-registry-", dest)
      begin
        files.each do |name, body|
          File.open(File.join(folder, name), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(body) }
        end
        commands = [[RbConfig.ruby, "-c", "registry.rb"], [RbConfig.ruby, "registry_test.rb"]]
        checks = commands.map do |cmd|
          stdout, stderr, status = Open3.capture3(*cmd, chdir: folder, unsetenv_others: false)
          { "command" => cmd.drop(1), "exit_code" => status.exitstatus,
            "output_sha256" => Digest::SHA256.hexdigest(stdout + stderr) }
        end
        raise Rejected, "generated code verification failed" unless checks.all? { |c| c["exit_code"] == 0 }
        manifest = { "schema_version" => 1, "state" => "verified_isolated_feature_slice",
          "ticket_id" => plan.fetch("ticket_id"), "tracking_key" => "STUDIO-203",
          "source_url" => plan.fetch("source_url"), "plan_sha256" => plan.fetch("fingerprint"),
          "roadmap_sha256" => Digest::SHA256.hexdigest(roadmap_bytes),
          "file_sha256" => files.transform_values { |v| Digest::SHA256.hexdigest(v) },
          "checks" => checks, "feature_complete" => false,
          "authorization" => "not_granted", "release_approved" => false,
          "note" => "Standalone registry lookup slice only; not merged with application or capability registry" }
        File.open(File.join(folder, "manifest.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(manifest) + "\n") }
        { "directory" => folder, "manifest" => manifest }
      rescue StandardError
        FileUtils.remove_entry(folder) if File.directory?(folder)
        raise
      end
    rescue JSON::ParserError, KeyError, TypeError => e
      raise Rejected, "invalid roadmap or plan: #{e.class}"
    end
  end
end
