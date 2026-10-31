# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../app/services/nevaeh_intelligences/yaml_capability_registry_v7a"
require_relative "../../app/services/nevaeh_intelligences/capability_console_v7a"

class NevaehEmptyRegistryTest < Minitest::Test
  Registry = NevaehIntelligences::YamlCapabilityRegistryV7a
  Console = NevaehIntelligences::CapabilityConsoleV7a

  def test_overview_list_handles_a_fresh_checkout_without_writing_configuration
    Dir.mktmpdir("nevaeh-empty-") do |root|
      assert_equal [], Console.list(root: root)
      refute File.exist?(File.join(root, "config"))
      assert_raises(Registry::Invalid) { Registry.read(root: root, key: "studio.project.create") }
    end
  end

  def test_placeholder_is_not_counted_as_a_capability_and_creation_still_works
    Dir.mktmpdir("nevaeh-placeholder-") do |root|
      directory = File.join(root, "config/nevaeh/capabilities")
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, ".gitkeep"), "")
      assert_equal [], Console.list(root: root)
      Registry.create(root: root, key: "studio.project.create", write: true)
      assert_equal [{"key" => "studio.project.create", "valid" => true, "jobs" => 0}], Console.list(root: root)
    end
  end

  def test_existing_invalid_configuration_is_not_hidden_as_an_empty_registry
    Dir.mktmpdir("nevaeh-invalid-") do |root|
      directory = File.join(root, "config/nevaeh/capabilities")
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "studio.project.create.yml"), "schema_version: 999\n")
      assert_raises(Registry::Invalid) { Console.list(root: root) }
    end
  end

  def test_symlinked_or_non_directory_registries_are_still_rejected
    Dir.mktmpdir("nevaeh-links-") do |root|
      directory = File.join(root, "config/nevaeh/capabilities")
      FileUtils.mkdir_p(File.dirname(directory))
      File.symlink(File.join(root, "missing-target"), directory)
      assert_raises(Registry::Invalid) { Console.list(root: root) }
      File.unlink(directory)
      File.write(directory, "not a directory")
      assert_raises(Registry::Invalid) { Console.list(root: root) }
    end
  end
end
