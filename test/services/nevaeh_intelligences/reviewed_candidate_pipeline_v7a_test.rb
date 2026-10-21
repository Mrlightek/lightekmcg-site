# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
class ReviewedCandidatePipelineV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    item = roadmap.fetch("items").find { |i| i.fetch("key") == "STUDIO-203" }
    issue = { "number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46", "title" => "[STUDIO-203] #{item.fetch('title')}", "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`" }
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 candidate test", category: "technical", priority: "high", status: "open", urgency: 5, extra_fields: { "project_tracking" => { "key" => "STUDIO-203" } })
    NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end
  def with_root
    Dir.mktmpdir("reviewed-pipeline-root-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      File.write(File.join(root, "config/nevaeh/trusted_services.yml"), "schema_version: 1\nservices: {}\n")
      registry = NevaehIntelligences::YamlCapabilityRegistryV7a
      registry.create(root: root, key: "test.normalize", write: true)
      registry.add_job(root: root, key: "test.normalize", id: "normalize", service: "nevaeh.metadata.normalize", after: [], write: true)
      yield root
    end
  end
  test "preview never approves execution or ticket acceptance" do
    with_root do |root|
      result = NevaehIntelligences::ReviewedCandidatePipelineV7a.preview(ticket: @ticket, key: "test.normalize", root: root)
      assert_equal false, result.fetch("ticket_acceptance_verified")
      assert_equal false, result.fetch("production_allowed")
      assert_equal false, result.fetch("job_integration_verified")
    end
  end
  test "generated Active Job runs reviewed service and produces separate evidence" do
    with_root do |root|
      Dir.mktmpdir("reviewed-pipeline-output-") do |outer|
        dest = File.join(outer, "candidate")
        result = NevaehIntelligences::ReviewedCandidatePipelineV7a.generate(ticket: @ticket, key: "test.normalize", destination: dest, root: root)
        assert result.fetch("service_unit_tests_passed")
        assert result.fetch("job_integration_verified"), result.fetch("job_test_output")
        assert_equal false, result.fetch("ticket_acceptance_verified")
        assert_equal false, result.fetch("source_promoted")
        assert File.file?(File.join(dest, "manifest.json"))
        assert File.file?(File.join(dest, "ticket_traceability.json"))
        assert File.file?(File.join(dest, "reviewed_candidate/verification.json"))
        assert File.file?(File.join(dest, "reviewed_candidate/job_verification.json"))
        assert_includes result.fetch("job_test_output"), "NEVAEH_REVIEWED_JOB_INTEGRATION_PASS"
      end
    end
  end
end
