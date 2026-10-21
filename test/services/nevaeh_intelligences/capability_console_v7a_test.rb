# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
class CapabilityConsoleV7aTest < ActiveSupport::TestCase
  test "empty registry produces read-only empty list" do
    Dir.mktmpdir("nevaeh-console-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      assert_equal [], NevaehIntelligences::CapabilityConsoleV7a.list(root: root)
    end
  end

  test "detail derives from same registry and reconciler without executing" do
    Dir.mktmpdir("nevaeh-console-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      registry = NevaehIntelligences::YamlCapabilityRegistryV7a
      registry.create(root: root, key: "studio.asset.ingest", write: true)
      registry.add_job(root: root, key: "studio.asset.ingest", id: "validate", service: "studio.asset.validate", write: true)
      result = NevaehIntelligences::CapabilityConsoleV7a.detail(root: root, key: "studio.asset.ingest")
      assert_equal "studio.asset.ingest", result.dig("definition", "capability", "key")
      assert_equal "unmapped", result.dig("reconciliation", "jobs", 0, "state")
      assert_equal false, result.fetch("execution_allowed")
    end
  end

  test "untrusted keys do not permit reading arbitrary files" do
    Dir.mktmpdir("nevaeh-console-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      assert_raises(NevaehIntelligences::YamlCapabilityRegistryV7a::Invalid) do
        NevaehIntelligences::CapabilityConsoleV7a.detail(root: root, key: "../secrets")
      end
    end
  end
end
