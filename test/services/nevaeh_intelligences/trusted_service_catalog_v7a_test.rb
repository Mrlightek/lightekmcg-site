# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
class TrustedServiceCatalogV7aTest < ActiveSupport::TestCase
  def with_root(content)
    Dir.mktmpdir("nevaeh-trusted-catalog-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh"))
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      FileUtils.mkdir_p(File.join(root, "app/services/studio"))
      File.write(File.join(root, "config/nevaeh/trusted_services.yml"), content)
      yield root
    end
  end
  def sample(path = "app/services/studio/validate.rb")
    { "schema_version" => 1, "services" => { "studio.asset.validate" => { "path" => path, "status" => "review_required" } } }.to_yaml
  end
  def test_catalog_reports_missing_without_execution
    with_root(sample) do |root|
      a = NevaehIntelligences::TrustedServiceCatalogV7a.inspect(root: root)
      assert_equal "missing", a.first.fetch("state")
      assert_equal false, a.first.fetch("executable")
      assert_nil a.first.fetch("sha256")
    end
  end
  def test_catalog_reports_present_checksum
    with_root(sample) do |root|
      File.write(File.join(root, "app/services/studio/validate.rb"), "module Studio; end\n")
      a = NevaehIntelligences::TrustedServiceCatalogV7a.inspect(root: root)
      assert_equal "present", a.first.fetch("state")
      assert_match(/\A[0-9a-f]{64}\z/, a.first.fetch("sha256"))
      assert_equal false, a.first.fetch("executable")
    end
  end
  def test_rejects_traversal
    with_root(sample("../../etc/passwd")) do |root|
      assert_raises(NevaehIntelligences::TrustedServiceCatalogV7a::Invalid) { NevaehIntelligences::TrustedServiceCatalogV7a.paths(root: root) }
    end
  end
  def test_rejects_yaml_aliases
    with_root("schema_version: 1\nservices: &s {}\nother: *s\n") do |root|
      assert_raises(NevaehIntelligences::TrustedServiceCatalogV7a::Invalid) { NevaehIntelligences::TrustedServiceCatalogV7a.paths(root: root) }
    end
  end
  def test_rejects_symlinked_path
    with_root(sample) do |root|
      File.symlink("/tmp", File.join(root, "app/services/studio/validate.rb"))
      assert_raises(NevaehIntelligences::TrustedServiceCatalogV7a::Invalid) { NevaehIntelligences::TrustedServiceCatalogV7a.paths(root: root) }
    end
  end
  def test_cli_lists_trusted_services_json
    with_root(sample) do |root|
      out, err = StringIO.new, StringIO.new
      code = NevaehIntelligences::CliV7a.run(["--format", "json", "config", "services"], root: root, out: out, err: err)
      assert_equal 0, code, err.string
      parsed = JSON.parse(out.string)
      assert_equal "studio.asset.validate", parsed.fetch("result").first.fetch("service")
      assert_equal false, parsed.fetch("result").first.fetch("executable")
    end
  end
  def test_reconcile_uses_trusted_mapping_not_yaml_path
    with_root(sample) do |root|
      reg = NevaehIntelligences::YamlCapabilityRegistryV7a
      reg.create(root: root, key: "studio.asset.ingest", write: true)
      reg.add_job(root: root, key: "studio.asset.ingest", id: "validate", service: "studio.asset.validate", write: true)
      out, err = StringIO.new, StringIO.new
      code = NevaehIntelligences::CliV7a.run(["--format", "json", "config", "reconcile", "studio.asset.ingest"], root: root, out: out, err: err)
      assert_equal 0, code, err.string
      assert_equal "missing", JSON.parse(out.string).fetch("result").fetch("jobs").first.fetch("state")
    end
  end
end
