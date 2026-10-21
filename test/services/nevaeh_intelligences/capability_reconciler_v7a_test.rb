# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"

class CapabilityReconcilerV7aTest < ActiveSupport::TestCase
  def with_root
    Dir.mktmpdir("nevaeh-reconcile-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      FileUtils.mkdir_p(File.join(root, "app/services/studio"))
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: root, key: "studio.asset.ingest", write: true)
      reg.add_job(root: root, key: "studio.asset.ingest", id: "validate", service: "studio.asset.validate", write: true)
      reg.add_job(root: root, key: "studio.asset.ingest", id: "process", service: "studio.asset.process", after: ["validate"], write: true)
      yield root
    end
  end

  def test_reports_present_missing_and_unmapped_without_execution
    with_root do |root|
      File.write(File.join(root, "app/services/studio/validate.rb"), "module Studio; end\n")
      p = NevaehIntelligences::CapabilityReconcilerV7a.plan(root: root, key: "studio.asset.ingest", service_paths: { "studio.asset.validate" => "app/services/studio/validate.rb", "studio.asset.process" => "app/services/studio/process.rb" })
      assert_equal %w[present missing], p.fetch("jobs").map { |j| j.fetch("state") }
      assert_equal "propose_generation", p.fetch("jobs")[1].fetch("action")
      assert_equal false, p.fetch("execution_allowed")
      assert_match(/\A[0-9a-f]{64}\z/, p.fetch("jobs")[0].fetch("sha256"))
      assert_nil p.fetch("jobs")[1].fetch("sha256")
    end
  end

  def test_unmapped_service_is_not_assumed_absent
    with_root do |root|
      p = NevaehIntelligences::CapabilityReconcilerV7a.plan(root: root, key: "studio.asset.ingest")
      assert_equal %w[unmapped unmapped], p.fetch("jobs").map { |j| j.fetch("state") }
      assert_equal "register_service_mapping", p.fetch("jobs")[0].fetch("action")
    end
  end

  def test_rejects_unsafe_service_mapping
    with_root do |root|
      assert_raises(NevaehIntelligences::CapabilityReconcilerV7a::Invalid) do
        NevaehIntelligences::CapabilityReconcilerV7a.plan(root: root, key: "studio.asset.ingest", service_paths: { "studio.asset.validate" => "../../etc/passwd" })
      end
    end
  end

  def test_rejects_symlinked_service
    with_root do |root|
      File.symlink("/tmp", File.join(root, "app/services/studio/bad.rb"))
      assert_raises(NevaehIntelligences::CapabilityReconcilerV7a::Invalid) do
        NevaehIntelligences::CapabilityReconcilerV7a.plan(root: root, key: "studio.asset.ingest", service_paths: { "studio.asset.validate" => "app/services/studio/bad.rb" })
      end
    end
  end

  def test_cli_reconcile_json_is_read_only
    with_root do |root|
      output, error = StringIO.new, StringIO.new
      code = NevaehIntelligences::CliV7a.run(["--format", "json", "config", "reconcile", "studio.asset.ingest"], root: root, out: output, err: error)
      assert_equal 0, code, error.string
      parsed = JSON.parse(output.string)
      assert_equal false, parsed.dig("result", "execution_allowed")
      assert_equal %w[unmapped unmapped], parsed.dig("result", "jobs").map { |j| j["state"] }
      assert_equal "", error.string
    end
  end
end
