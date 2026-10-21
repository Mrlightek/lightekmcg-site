# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
class CapabilityCodeGeneratorV7aTest < ActiveSupport::TestCase
  def with_workspace
    Dir.mktmpdir("nevaeh8k") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      FileUtils.mkdir_p(File.join(root, "app/services"))
      File.write(File.join(root, "config/nevaeh/trusted_services.yml"), "schema_version: 1\nservices: {}\n")
      NevaehIntelligences::YamlCapabilityRegistryV7a.create(root: root, key: "test.build", write: true)
      NevaehIntelligences::YamlCapabilityRegistryV7a.add_job(root: root, key: "test.build", id: "analyze", service: "test.analyze", after: [], write: true)
      NevaehIntelligences::YamlCapabilityRegistryV7a.add_job(root: root, key: "test.build", id: "generate", service: "test.generate", after: ["analyze"], write: true)
      yield root
    end
  end
  def test_plan_has_two_jobs_and_dependency
    with_workspace do |root|
      plan = NevaehIntelligences::CapabilityCodeGeneratorV7a.plan(root: root, key: "test.build")
      assert_equal 2, plan.fetch("jobs").size
      assert_equal ["analyze"], plan.fetch("jobs").last.fetch("dependencies")
      assert_equal false, plan.fetch("enabled")
    end
  end
  def test_generates_files_in_isolated_directory_and_checksums
    with_workspace do |root|
      Dir.mktmpdir("nevaeh8k-output") do |parent|
        dest = File.join(parent, "draft")
        result = NevaehIntelligences::CapabilityCodeGeneratorV7a.generate(root: root, key: "test.build", destination: dest)
        assert_equal false, result.fetch("executable")
        assert_equal false, result.fetch("verified_implementation")
        assert_equal 7, result.fetch("artifact_sha256").length
        assert File.file?(File.join(dest, "jobs/generate_job.rb"))
        assert_equal result.fetch("artifact_sha256").fetch("jobs/generate_job.rb"), Digest::SHA256.file(File.join(dest, "jobs/generate_job.rb")).hexdigest
      end
    end
  end
  def test_refuses_existing_destination
    with_workspace do |root|
      assert_raises(NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid) do
        NevaehIntelligences::CapabilityCodeGeneratorV7a.generate(root: root, key: "test.build", destination: root)
      end
    end
  end
  def test_generated_file_is_inert
    with_workspace do |root|
      Dir.mktmpdir("nevaeh8k-output") do |parent|
        dest = File.join(parent, "draft")
        NevaehIntelligences::CapabilityCodeGeneratorV7a.generate(root: root, key: "test.build", destination: dest)
        assert_includes File.read(File.join(dest, "jobs/analyze_job.rb")), "NotImplementedError"
        assert_includes File.read(File.join(dest, "README.md")), "not executable"
      end
    end
  end
end
