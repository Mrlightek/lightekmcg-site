# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

class YamlCapabilityRegistryV7aTest < ActiveSupport::TestCase
  def with_root
    Dir.mktmpdir("nevaeh-yaml-") do |dir|
      FileUtils.mkdir_p(File.join(dir, "config/nevaeh/capabilities"))
      yield dir
    end
  end

  def test_draft_is_disabled_and_gatekeeper_required
    data = NevaehIntelligences::YamlCapabilityRegistryV7a.draft("studio.asset.ingest")
    assert_equal false, data.dig("capability", "enabled")
    assert_equal true, data.dig("capability", "authorization", "gatekeeper_required")
  end

  def test_write_and_read_and_list
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest", write: true)
      assert_equal "studio.asset.ingest", reg.read(root: dir, key: "studio.asset.ingest").dig("capability", "key")
      assert_equal 1, reg.list(root: dir).size
    end
  end

  def test_dry_run_does_not_write
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest")
      assert_empty reg.list(root: dir)
    end
  end

  def test_no_overwrite
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest", write: true)
      assert_raises(reg::Invalid) { reg.create(root: dir, key: "studio.asset.ingest", write: true) }
    end
  end

  def test_add_job_with_dependency
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest", write: true)
      reg.add_job(root: dir, key: "studio.asset.ingest", id: "validate", service: "studio.asset.validate", write: true)
      reg.add_job(root: dir, key: "studio.asset.ingest", id: "process", service: "studio.asset.process", after: ["validate"], write: true)
      assert_equal ["validate"], reg.read(root: dir, key: "studio.asset.ingest").dig("capability", "jobs", 1, "depends_on")
    end
  end

  def test_rejects_unknown_dependency
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest", write: true)
      assert_raises(reg::Invalid) { reg.add_job(root: dir, key: "studio.asset.ingest", id: "process", service: "studio.asset.process", after: ["unknown"], write: true) }
    end
  end

  def test_rejects_unsafe_key
    reg = NevaehIntelligences::YamlCapabilityRegistryV7a
    assert_raises(reg::Invalid) { reg.draft("../../etc/passwd") }
  end

  def test_rejects_yaml_aliases_and_gatekeeper_disable
    with_root do |dir|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: dir, key: "studio.asset.ingest", write: true)
      loc = reg.path(dir, "studio.asset.ingest")
      data = reg.read(root: dir, key: "studio.asset.ingest")
      data["capability"]["authorization"]["gatekeeper_required"] = false
      File.write(loc, YAML.dump(data))
      assert_raises(reg::Invalid) { reg.read(root: dir, key: "studio.asset.ingest") }
    end
  end

  def test_cli_json_preview_and_unknown_command
    out, err = StringIO.new, StringIO.new
    status = NevaehIntelligences::CliV7a.run(["--format", "json", "config", "create", "studio.asset.ingest"], out: out, err: err)
    assert_equal 0, status
    assert_equal false, JSON.parse(out.string).dig("result", "capability", "enabled")
    assert_equal "", err.string
    assert_equal 2, NevaehIntelligences::CliV7a.run(["config", "run", "studio.asset.ingest"], out: StringIO.new, err: StringIO.new)
  end
end
