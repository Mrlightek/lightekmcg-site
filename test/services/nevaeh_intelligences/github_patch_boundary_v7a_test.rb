# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "json"
require "digest"

class GithubPatchBoundaryV7aTest < ActiveSupport::TestCase
  def plan(key)
    { "status" => "planning_only", "execution_enabled" => false, "tracking_key" => key,
      "ticket_id" => 123, "fingerprint" => Digest::SHA256.hexdigest(key),
      "gatekeeper" => { "authorization_required" => true, "production_execution_allowed" => false, "human_release_approval_required" => true } }
  end

  def package(p, changes, root)
    NevaehIntelligences::GithubPatchBoundaryV7a.package(plan: p, changes: changes, root: root)
  end

  def test_packages_two_different_ticket_proposals_without_template_switch
    { "STUDIO-203" => { "app/services/studio/generated_capability_registry.rb" => "module Studio; module GeneratedCapabilityRegistry; def self.ids; []; end; end; end\n" },
      "STUDIO-401" => { "app/services/studio/generated_template_snapshot.rb" => "module Studio; module GeneratedTemplateSnapshot; def self.snapshot(value); value.dup; end; end; end\n" } }.each do |key, files|
      Dir.mktmpdir do |root|
        output = package(plan(key), files, root)
        manifest = output.fetch("manifest")
        assert_equal key, manifest.fetch("tracking_key")
        assert_equal false, manifest.fetch("feature_complete")
        assert_equal false, manifest.fetch("tests_executed")
        file = manifest.fetch("files").first
        assert_equal Digest::SHA256.hexdigest(files.values.first), file.fetch("sha256")
        assert File.file?(File.join(output.fetch("directory"), "files", files.keys.first))
      end
    end
  end

  def test_rejects_path_traversal
    Dir.mktmpdir do |root|
      assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(plan("STUDIO-203"), { "app/services/../../evil.rb" => "x" }, root) }
    end
  end

  def test_rejects_existing_application_file
    Dir.mktmpdir do |root|
      assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(plan("STUDIO-203"), { "app/services/nevaeh_intelligences/github_development_plan_v7a.rb" => "x" }, root) }
    end
  end

  def test_invalid_ruby_removed_without_artifacts
    Dir.mktmpdir do |root|
      assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(plan("STUDIO-203"), { "app/services/studio/new_broken.rb" => "module Invalid (" }, root) }
      assert_empty Dir.children(root)
    end
  end

  def test_rejects_execution_enabled_or_missing_gatekeeper
    Dir.mktmpdir do |root|
      p = plan("STUDIO-203"); p["execution_enabled"] = true
      assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(p, { "app/services/studio/new_safe.rb" => "module Safe; end" }, root) }
      p = plan("STUDIO-203"); p["gatekeeper"]["authorization_required"] = false
      assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(p, { "app/services/studio/new_safe.rb" => "module Safe; end" }, root) }
    end
  end

  def test_rejects_repository_root
    assert_raises(NevaehIntelligences::GithubPatchBoundaryV7a::Rejected) { package(plan("STUDIO-203"), { "app/services/studio/new_safe.rb" => "module Safe; end" }, Rails.root.to_s) }
  end
end
