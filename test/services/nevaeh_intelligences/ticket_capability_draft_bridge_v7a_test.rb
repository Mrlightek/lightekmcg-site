# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "securerandom"
require "json"
require "digest"

class TicketCapabilityDraftBridgeV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    assert item, "STUDIO-203 roadmap fixture missing"
    issue = {"number" => 46, "state" => "open",
      "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{item.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"}
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 bridge test", category: "technical", priority: "high", status: "open", urgency: 5,
      extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
    assert_equal :attached, NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end

  def with_capability
    Dir.mktmpdir("nevaeh-ticket-bridge-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      # Generator V7a reads the catalog from the provided isolated root.
      # Keep the real catalog validation intact; supply the minimal valid fixture.
      File.write(File.join(root, "config/nevaeh/trusted_services.yml"), "schema_version: 1\nservices: {}\n")
      NevaehIntelligences::YamlCapabilityRegistryV7a.create(root: root, key: "test.build", write: true)
      NevaehIntelligences::YamlCapabilityRegistryV7a.add_job(root: root, key: "test.build", id: "analyze", service: "test.analyze", after: [], write: true)
      yield root
    end
  end

  test "preview links persisted ticket and explicit capability without asserting completion" do
    with_capability do |root|
      info = NevaehIntelligences::TicketCapabilityDraftBridgeV7a.preview(ticket: @ticket, capability_key: "test.build", root: root)
      assert_equal "STUDIO-203", info.fetch("tracking_key")
      assert_equal "test.build", info.fetch("capability_key")
      assert_equal "review_only", info.fetch("status")
      assert_equal false, info.fetch("acceptance_verified")
      assert_equal false, info.fetch("executable")
      assert_equal 1, info.fetch("capability_plan").fetch("jobs").length
    end
  end

  test "generate retains ticket evidence alongside inert Rails draft" do
    with_capability do |root|
      Dir.mktmpdir("nevaeh-external-") do |external|
        destination = File.join(external, "ticket-draft")
        result = NevaehIntelligences::TicketCapabilityDraftBridgeV7a.generate(ticket: @ticket, capability_key: "test.build", root: root, destination: destination)
        assert File.file?(File.join(destination, "manifest.json"))
        assert File.file?(File.join(destination, "ticket_traceability.json"))
        evidence = JSON.parse(File.read(File.join(destination, "ticket_traceability.json")))
        assert_equal "STUDIO-203", evidence.fetch("tracking_key")
        assert_equal false, evidence.fetch("implementation_verified")
        assert_equal Digest::SHA256.file(File.join(destination, "manifest.json")).hexdigest, evidence.fetch("generator_manifest_sha256")
        assert_equal File.realpath(destination), File.realpath(result.fetch("destination"))
      end
    end
  end

  test "rejects missing capability without generating" do
    with_capability do |root|
      Dir.mktmpdir("nevaeh-external-") do |external|
        destination = File.join(external, "missing")
        assert_raises(NevaehIntelligences::TicketCapabilityDraftBridgeV7a::Rejected) do
          NevaehIntelligences::TicketCapabilityDraftBridgeV7a.generate(ticket: @ticket, capability_key: "missing.#{SecureRandom.hex(3)}", root: root, destination: destination)
        end
        refute File.exist?(destination)
      end
    end
  end

  test "rejects reuse of destination rather than overwriting" do
    with_capability do |root|
      Dir.mktmpdir("nevaeh-external-") do |external|
        assert_raises(NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid) do
          NevaehIntelligences::TicketCapabilityDraftBridgeV7a.generate(ticket: @ticket, capability_key: "test.build", root: root, destination: external)
        end
      end
    end
  end
end
