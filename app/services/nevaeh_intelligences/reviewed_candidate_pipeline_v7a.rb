# frozen_string_literal: true
require "json"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"
module NevaehIntelligences
  # Executes only static reviewed candidate verification, not an untrusted ticket body.
  # The generated Active Job is invoked synchronously in a disposable subprocess.
  module ReviewedCandidatePipelineV7a
    class Rejected < StandardError; end
    module_function
    def preview(ticket:, key:, root: Rails.root.to_s)
      raise Rejected, "local review access denied" unless TicketDraftAccessV7a.allowed?
      ReviewedImplementationTemplateV7a.preview(ticket: ticket, key: key, root: root).merge(
        "job_integration_verified" => false, "ticket_acceptance_verified" => false,
        "production_allowed" => false, "source_promoted" => false)
    end
    def generate(ticket:, key:, destination:, root: Rails.root.to_s)
      preview(ticket: ticket, key: key, root: root)
      base = nil
      begin
        info = ReviewedImplementationTemplateV7a.generate(ticket: ticket, key: key, destination: destination, root: root)
        base = File.realpath(destination)
        candidate = File.join(base, "reviewed_candidate")
        service = File.join(candidate, "services/metadata_normalizer.rb")
        job = File.join(candidate, "jobs/metadata_normalization_job.rb")
        [service, job].each { |path| raise Rejected, "missing generated file" unless File.file?(path) && !File.symlink?(path) }
        # Constant template sources, compared to the trusted implementation embedded in code.
        template = ReviewedImplementationTemplateV7a
        raise Rejected, "service changed" unless Digest::SHA256.file(service).hexdigest == Digest::SHA256.hexdigest(template.service_source)
        raise Rejected, "job changed" unless Digest::SHA256.file(job).hexdigest == Digest::SHA256.hexdigest(template.job_source)
        script = <<~'CHECK'
          require "json"
          require ARGV.fetch(0)
          require ARGV.fetch(1)
          result = NevaehGenerated::MetadataNormalizationJob.perform_now({ "name" => "  Jane   Doe " })
          raise "incorrect job result" unless result == { "name" => "Jane Doe" }
          begin
            NevaehGenerated::MetadataNormalizationJob.perform_now({ "Bad Key" => "invalid" })
            raise "invalid metadata accepted"
          rescue ArgumentError
          end
          puts "NEVAEH_REVIEWED_JOB_INTEGRATION_PASS"
        CHECK
        output, errors, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup", "-ractive_job", "-e", script, service, job, chdir: candidate)
        evidence = {
          "schema_version" => 1, "template" => "metadata.normalize.v1",
          "ticket_id" => ticket.id, "capability" => key,
          "job_integration_verified" => status.success?,
          "job_test_exit_status" => status.exitstatus,
          "job_test_output" => (output + errors).byteslice(0, 6000),
          "job_sha256" => Digest::SHA256.file(job).hexdigest,
          "service_sha256" => Digest::SHA256.file(service).hexdigest,
          "service_unit_tests_passed" => info.fetch("service_unit_tests_passed"),
          "ticket_acceptance_verified" => false,
          "gatekeeper_approved" => false, "production_allowed" => false,
          "source_promoted" => false, "executable_in_production" => false
        }
        File.open(File.join(candidate, "job_verification.json"), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(evidence) + "\n") }
        raise Rejected, "Active Job verification failed" unless status.success?
        evidence.merge("destination" => base)
      rescue StandardError
        FileUtils.remove_entry_secure(base) if base && File.directory?(base) && !File.symlink?(base)
        raise
      end
    end
  end
end
