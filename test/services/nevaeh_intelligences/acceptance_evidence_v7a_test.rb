# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "json"
require "digest"
require "fileutils"
class AcceptanceEvidenceV7aTest < ActiveSupport::TestCase
  def with_fixture
    Dir.mktmpdir("nevaeh-reviewed-evidence-") do |base|
      FileUtils.mkdir_p(File.join(base, "reviewed_candidate/services"))
      FileUtils.mkdir_p(File.join(base, "reviewed_candidate/jobs"))
      File.write(File.join(base, "manifest.json"), "{}")
      svc = File.join(base, "reviewed_candidate/services/metadata_normalizer.rb")
      job = File.join(base, "reviewed_candidate/jobs/metadata_normalization_job.rb")
      File.write(svc, "# service\n")
      File.write(job, "# job\n")
      hash = ->(file) { Digest::SHA256.file(file).hexdigest }
      trace = {"ticket_id" => 17, "tracking_key" => "STUDIO-203", "capability_key" => "test.normalize", "acceptance_criteria" => ["Build correct feature"], "generator_manifest_sha256" => hash.call(File.join(base, "manifest.json"))}
      unit = {"template" => "metadata.normalize.v1", "capability" => "test.normalize", "service_unit_tests_passed" => true, "artifact_sha256" => {"services/metadata_normalizer.rb" => hash.call(svc), "jobs/metadata_normalization_job.rb" => hash.call(job)}}
      integration = {"template" => "metadata.normalize.v1", "ticket_id" => 17, "capability" => "test.normalize", "service_sha256" => hash.call(svc), "job_sha256" => hash.call(job), "job_integration_verified" => true}
      {"ticket_traceability.json" => trace, "reviewed_candidate/verification.json" => unit, "reviewed_candidate/job_verification.json" => integration}.each do |relative, data|
        File.write(File.join(base, relative), JSON.generate(data))
      end
      yield base
    end
  end
  test "valid evidence still leaves ticket criteria unverified" do
    with_fixture do |base|
      result = NevaehIntelligences::AcceptanceEvidenceV7a.inspect_bundle(destination: base)
      assert_equal true, result.fetch("integrity_verified")
      assert_equal true, result.fetch("service_tests_passed")
      assert_equal true, result.fetch("job_integration_tests_passed")
      assert_equal "unverified", result.fetch("acceptance_criteria").first.fetch("status")
      assert_equal false, result.fetch("acceptance_verified")
      assert_equal false, result.fetch("gatekeeper_approved")
    end
  end
  test "tampered service downgrades integrity rather than claiming test success" do
    with_fixture do |base|
      File.write(File.join(base, "reviewed_candidate/services/metadata_normalizer.rb"), "tampered")
      result = NevaehIntelligences::AcceptanceEvidenceV7a.inspect_bundle(destination: base)
      assert_equal false, result.fetch("integrity_verified")
      assert_equal false, result.fetch("service_tests_passed")
      assert_equal "integrity_failure", result.fetch("status")
    end
  end
  test "refuses symlinked evidence" do
    with_fixture do |base|
      file = File.join(base, "ticket_traceability.json")
      data = File.read(file)
      File.delete(file)
      target = File.join(base, "target.json")
      File.write(target, data)
      File.symlink(target, file)
      assert_raises(NevaehIntelligences::AcceptanceEvidenceV7a::Rejected) { NevaehIntelligences::AcceptanceEvidenceV7a.inspect_bundle(destination: base) }
    end
  end
end
