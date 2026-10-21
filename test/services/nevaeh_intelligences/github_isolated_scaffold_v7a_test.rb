# frozen_string_literal: true
require "test_helper"
require "json"
require "tmpdir"
require "digest"

class GithubIsolatedScaffoldV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    assert item
    issue = {"number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"}
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 scaffold", category: "technical", priority: "high", status: "open", urgency: 5,
      extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
    assert_equal :attached, NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end

  def test_creates_isolated_scaffold_with_auditable_manifest
    Dir.mktmpdir("v7a5-outside-") do |root|
      result = NevaehIntelligences::GithubIsolatedScaffoldV7a.build_from_ticket(ticket: @ticket, root: root)
      assert result.fetch("directory").start_with?(File.realpath(root) + File::SEPARATOR)
      source = File.read(File.join(result.fetch("directory"), "scaffold.rb"))
      manifest = JSON.parse(File.read(File.join(result.fetch("directory"), "manifest.json")))
      assert_equal Digest::SHA256.hexdigest(source), manifest.fetch("source_sha256")
      assert_equal "scaffold_only_not_implemented", manifest.fetch("state")
      assert_equal false, manifest.fetch("feature_complete")
      assert_equal false, manifest.fetch("tests_executed")
      assert_includes source, "raise NotImplementedError"
    end
  end

  def test_new_directory_for_each_run_and_no_work_order_change
    Dir.mktmpdir("v7a5-outside-") do |root|
      before = @ticket.reload.extra_fields.deep_dup
      a = NevaehIntelligences::GithubIsolatedScaffoldV7a.build_from_ticket(ticket: @ticket, root: root)
      b = NevaehIntelligences::GithubIsolatedScaffoldV7a.build_from_ticket(ticket: @ticket, root: root)
      refute_equal a.fetch("directory"), b.fetch("directory")
      assert_equal before, @ticket.reload.extra_fields
    end
  end

  def test_refuses_repository_as_output_location
    assert_raises(NevaehIntelligences::GithubIsolatedScaffoldV7a::Rejected) do
      NevaehIntelligences::GithubIsolatedScaffoldV7a.build_from_ticket(ticket: @ticket, root: Rails.root.to_s)
    end
  end

  def test_refuses_reserved_ticket
    @ticket.update!(extra_fields: @ticket.extra_fields.deep_merge("nevaeh" => {"execution_status" => "dispatch_reserved"}))
    Dir.mktmpdir("v7a5-outside-") do |root|
      assert_raises(NevaehIntelligences::GithubDevelopmentPlanV7a::Rejected) do
        NevaehIntelligences::GithubIsolatedScaffoldV7a.build_from_ticket(ticket: @ticket, root: root)
      end
    end
  end
end
