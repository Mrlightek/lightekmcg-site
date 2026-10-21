# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"
module NevaehIntelligences
  # Exactly one fixed reviewed template. Never execute source text from tickets or YAML.
  module ReviewedImplementationTemplateV7a
    class Rejected < StandardError; end
    SERVICE_ID = "nevaeh.metadata.normalize"
    module_function

    def preview(ticket:, key:, root: Rails.root.to_s)
      trace = TicketCapabilityDraftBridgeV7a.preview(ticket: ticket, capability_key: key, root: root)
      jobs = trace.fetch("capability_plan").fetch("jobs")
      raise Rejected, "template requires exactly one job" unless jobs.size == 1
      raise Rejected, "service is not reviewed template" unless jobs.first.fetch("service") == SERVICE_ID
      raise Rejected, "template requires no dependencies" unless jobs.first.fetch("dependencies") == []
      { "ticket" => trace.fetch("tracking_key"), "key" => key, "template" => "metadata.normalize.v1", "status" => "proposal_only", "acceptance_verified" => false, "gatekeeper_approved" => false }
    end

    def generate(ticket:, key:, destination:, root: Rails.root.to_s)
      preview_info = preview(ticket: ticket, key: key, root: root)
      # Bridge owns original generator manifest; do not change any of its artifacts.
      TicketCapabilityDraftBridgeV7a.generate(ticket: ticket, capability_key: key, destination: destination, root: root)
      base = File.realpath(destination)
      begin
        candidate = File.join(base, "reviewed_candidate")
        Dir.mkdir(candidate, 0o700)
        { "services" => service_source, "jobs" => job_source, "tests" => test_source }.each_key do |dir|
          Dir.mkdir(File.join(candidate, dir), 0o700)
        end
        artifacts = { "services/metadata_normalizer.rb" => service_source,
                      "jobs/metadata_normalization_job.rb" => job_source,
                      "tests/metadata_normalizer_test.rb" => test_source,
                      "README.md" => "# Reviewed template candidate\n\nFunctional metadata normalization service with an ActiveJob wrapper.\nThe isolated unit tests cover the service only, not the job adapter or ticket acceptance criteria.\nNo deployment, authorization, or source promotion.\n" }
        artifacts.each do |relative, content|
          path = File.join(candidate, relative)
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(content) }
        end
        command = [RbConfig.ruby, "--disable-gems", "-I", File.join(candidate, "services"), File.join(candidate, "tests/metadata_normalizer_test.rb")]
        output, errors, process = Open3.capture3(*command, chdir: candidate)
        verified = process.success?
        verification = { "schema_version" => 1, "ticket" => preview_info.fetch("ticket"), "capability" => key,
          "template" => "metadata.normalize.v1", "reviewed_template_source" => "static_allowlisted_v7a",
          "artifact_sha256" => artifacts.transform_values { |v| Digest::SHA256.hexdigest(v) },
          "service_unit_tests_passed" => verified, "unit_test_exit_status" => process.exitstatus,
          "unit_test_output" => (output + errors).byteslice(0, 6000), "job_integration_verified" => false,
          "ticket_acceptance_verified" => false, "gatekeeper_approved" => false,
          "production_allowed" => false, "source_promoted" => false }
        File.open(File.join(candidate, "verification.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(verification) + "\n") }
        raise Rejected, "isolated service unit tests failed" unless verified
        verification.merge("destination" => base)
      rescue StandardError
        FileUtils.remove_entry_secure(base) if File.directory?(base) && !File.symlink?(base)
        raise
      end
    end

    def service_source
      <<~'SRC'
        # frozen_string_literal: true
        # Review-only metadata transformation with no database or network effects.
        module NevaehGenerated
          module MetadataNormalizer
            module_function
            def call(input)
              raise ArgumentError, "metadata must be a Hash" unless input.is_a?(Hash)
              raise ArgumentError, "too many fields" if input.size > 40
              result = {}
              input.each do |key, value|
                raise ArgumentError, "invalid field name" unless key.is_a?(String) && /\A[a-z][a-z0-9_]{0,63}\z/.match?(key)
                raise ArgumentError, "invalid field value" unless value.is_a?(String) && value.bytesize <= 512
                result[key] = value.strip.gsub(/[[:space:]]+/, " ")
              end
              result.sort.to_h.freeze
            end
          end
        end
      SRC
    end
    def job_source
      <<~'SRC'
        # frozen_string_literal: true
        require_relative "../services/metadata_normalizer"
        module NevaehGenerated
          class MetadataNormalizationJob < ActiveJob::Base
            queue_as :default
            def perform(input)
              NevaehGenerated::MetadataNormalizer.call(input)
            end
          end
        end
      SRC
    end
    def test_source
      <<~'SRC'
        # frozen_string_literal: true
        require "metadata_normalizer"
        def assert_equal(expected, actual)
          raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
        end
        assert_equal({"name" => "Jane Doe"}, NevaehGenerated::MetadataNormalizer.call({"name" => " Jane   Doe "}))
        assert_equal({"a" => "two", "z" => "one"}, NevaehGenerated::MetadataNormalizer.call({"z" => " one ", "a" => " two "}))
        [{"Name" => "bad"}, {"valid" => 12}, {"valid" => "x" * 513}, "not-a-hash"].each do |bad|
          begin
            NevaehGenerated::MetadataNormalizer.call(bad)
            raise "expected rejection"
          rescue ArgumentError
          end
        end
        puts "REVIEWED_TEMPLATE_SERVICE_TESTS_PASS"
      SRC
    end
  end
end
