# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "json"
require "digest"
require "fileutils"
class AcceptanceCoverageV7aTest < ActiveSupport::TestCase
  def with_fixture
    Dir.mktmpdir("nevaeh-reviewed-coverage-") do |base|
      FileUtils.mkdir_p(File.join(base, "reviewed_candidate/services"))
      FileUtils.mkdir_p(File.join(base, "reviewed_candidate/jobs"))
      File.write(File.join(base, "manifest.json"), "{}")
      svc = File.join(base, "reviewed_candidate/services/metadata_normalizer.rb")
      job = File.join(base, "reviewed_candidate/jobs/metadata_normalization_job.rb")
      File.write(svc, "# service\n")
      File.write(job, "# job\n")
      hash = ->(file) { Digest::SHA256.file(file).hexdigest }
      trace = {"ticket_id" => 17, "tracking_key" => "STUDIO-203", "capability_key" => "test.normalize", "acceptance_criteria" => ["Build feature", "Test job"], "generator_manifest_sha256" => hash.call(File.join(base, "manifest.json"))}
      unit = {"template" => "metadata.normalize.v1", "capability" => "test.normalize", "service_unit_tests_passed" => true, "artifact_sha256" => {"services/metadata_normalizer.rb" => hash.call(svc), "jobs/metadata_normalization_job.rb" => hash.call(job)}}
      integration = {"template" => "metadata.normalize.v1", "ticket_id" => 17, "capability" => "test.normalize", "service_sha256" => hash.call(svc), "job_sha256" => hash.call(job), "job_integration_verified" => true}
      {"ticket_traceability.json" => trace, "reviewed_candidate/verification.json" => unit, "reviewed_candidate/job_verification.json" => integration}.each { |relative, data| File.write(File.join(base, relative), JSON.generate(data)) }
      yield base
    end
  end
  def put_map(base, mappings)
    File.write(File.join(base, "coverage_mapping.json"), JSON.generate({"schema_version" => 1, "mappings" => mappings}))
  end
  test "unmapped requirements stay unverified" do
    with_fixture do |base|
      report = NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base)
      assert_equal %w[unmapped unmapped], report.fetch("acceptance_criteria").map { |c| c.fetch("status") }
      assert_equal false, report.fetch("acceptance_verified")
    end
  end
  test "valid links are pending independent review not accepted" do
    with_fixture do |base|
      put_map(base, [{"criterion_index" => 1, "evidence_type" => "service_unit_tests"}])
      report = NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base)
      assert_equal "mapped_pending_independent_review", report.fetch("acceptance_criteria").first.fetch("status")
      assert_equal "unmapped", report.fetch("acceptance_criteria").last.fetch("status")
      assert_equal 0, report.fetch("accepted_criteria_count")
      assert_equal false, report.fetch("gatekeeper_approved")
    end
  end
  test "invalid and duplicate references fail closed" do
    with_fixture do |base|
      put_map(base, [{"criterion_index" => 3, "evidence_type" => "service_unit_tests"}])
      assert_raises(NevaehIntelligences::AcceptanceCoverageV7a::Rejected) { NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base) }
      put_map(base, [{"criterion_index" => 1, "evidence_type" => "service_unit_tests"}] * 2)
      assert_raises(NevaehIntelligences::AcceptanceCoverageV7a::Rejected) { NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base) }
    end
  end
  test "tampering fails integrity and invalidates links" do
    with_fixture do |base|
      put_map(base, [{"criterion_index" => 1, "evidence_type" => "service_unit_tests"}])
      File.write(File.join(base, "reviewed_candidate/services/metadata_normalizer.rb"), "tamper")
      report = NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base)
      assert_equal "integrity_failure", report.fetch("acceptance_criteria").first.fetch("status")
      assert_equal false, report.fetch("acceptance_verified")
    end
  end
  test "symlinked mapping is rejected" do
    with_fixture do |base|
      target = File.join(base, "target.json")
      File.write(target, JSON.generate({"schema_version" => 1, "mappings" => []}))
      File.symlink(target, File.join(base, "coverage_mapping.json"))
      assert_raises(NevaehIntelligences::AcceptanceCoverageV7a::Rejected) { NevaehIntelligences::AcceptanceCoverageV7a.inspect_bundle(destination: base) }
    end
  end
end
