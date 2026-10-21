# frozen_string_literal: true
require "test_helper"
require "json"
require "tmpdir"
require "digest"

class GithubRegistrySliceV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    assert item
    issue = { "number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`" }
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 isolated slice", category: "technical", priority: "high", status: "open", urgency: 5,
      extra_fields: { "project_tracking" => { "key" => "STUDIO-203" } })
    assert_equal :attached, NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end

  def test_generates_real_isolated_code_and_test_evidence
    Dir.mktmpdir("nevaeh-7a6-outside-") do |root|
      original = @ticket.reload.extra_fields.deep_dup
      output = NevaehIntelligences::GithubRegistrySliceV7a.build_from_ticket(ticket: @ticket, root: root)
      folder = output.fetch("directory")
      assert folder.start_with?(File.realpath(root) + File::SEPARATOR)
      manifest = JSON.parse(File.read(File.join(folder, "manifest.json")))
      assert_equal "verified_isolated_feature_slice", manifest.fetch("state")
      assert_equal false, manifest.fetch("feature_complete")
      assert_equal false, manifest.fetch("release_approved")
      assert_equal [0, 0], manifest.fetch("checks").map { |c| c.fetch("exit_code") }
      manifest.fetch("file_sha256").each do |name, sha|
        assert_equal sha, Digest::SHA256.file(File.join(folder, name)).hexdigest
      end
      assert_equal original, @ticket.reload.extra_fields
    end
  end

  def test_rejects_application_tree
    assert_raises(NevaehIntelligences::GithubRegistrySliceV7a::Rejected) do
      NevaehIntelligences::GithubRegistrySliceV7a.build_from_ticket(ticket: @ticket, root: Rails.root.to_s)
    end
  end

  def test_rejects_reserved_ticket
    @ticket.update!(extra_fields: @ticket.extra_fields.deep_merge("nevaeh" => { "execution_status" => "dispatch_reserved" }))
    Dir.mktmpdir("nevaeh-7a6-outside-") do |root|
      assert_raises(NevaehIntelligences::GithubDevelopmentPlanV7a::Rejected) do
        NevaehIntelligences::GithubRegistrySliceV7a.build_from_ticket(ticket: @ticket, root: root)
      end
    end
  end
end
