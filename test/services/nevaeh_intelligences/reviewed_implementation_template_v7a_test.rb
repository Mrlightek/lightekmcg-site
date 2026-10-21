# frozen_string_literal: true
require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "json"
class ReviewedImplementationTemplateV7aTest < ActiveSupport::TestCase
  def setup
    roadmap = JSON.parse(Rails.root.join("config/project_tracking/lightek_studio.json").read)
    issue = {"number" => 46, "state" => "open", "html_url" => "https://github.com/Mrlightek/lightekmcg-site/issues/46",
      "title" => "[STUDIO-203] #{roadmap.fetch('items').find { |x| x.fetch('key') == 'STUDIO-203' }.fetch('title')}",
      "body" => "<!-- LIGHTEK_STUDIO_KEY:STUDIO-203 -->\n\n`config/project_tracking/lightek_studio.json`"}
    proposal = NevaehIntelligences::GithubWorkOrderProposalV7a.from_issue(issue, roadmap: roadmap)
    @ticket = Marlon::Ticket.create!(title: "STUDIO-203 reviewed template test", category: "technical", priority: "high", status: "open", urgency: 5, extra_fields: {"project_tracking" => {"key" => "STUDIO-203"}})
    NevaehIntelligences::GithubTicketPersistenceV7a.attach!(ticket: @ticket, proposal: proposal)
  end
  def with_root(service: "nevaeh.metadata.normalize")
    Dir.mktmpdir("nevaeh-reviewed-root-") do |root|
      FileUtils.mkdir_p(File.join(root, "config/nevaeh/capabilities"))
      File.write(File.join(root, "config/nevaeh/trusted_services.yml"), "schema_version: 1\nservices: {}\n")
      registry = NevaehIntelligences::YamlCapabilityRegistryV7a
      registry.create(root: root, key: "test.normalize", write: true)
      registry.add_job(root: root, key: "test.normalize", id: "normalize", service: service, after: [], write: true)
      yield root
    end
  end
  test "preview rejects unreviewed service identifier" do
    with_root(service: "danger.unreviewed") do |root|
      assert_raises(NevaehIntelligences::ReviewedImplementationTemplateV7a::Rejected) do
        NevaehIntelligences::ReviewedImplementationTemplateV7a.preview(ticket: @ticket, key: "test.normalize", root: root)
      end
    end
  end
  test "generates reviewed working service and isolation evidence without promoting" do
    with_root do |root|
      Dir.mktmpdir("nevaeh-reviewed-outer-") do |parent|
        destination = File.join(parent, "draft")
        info = NevaehIntelligences::ReviewedImplementationTemplateV7a.generate(ticket: @ticket, key: "test.normalize", destination: destination, root: root)
        assert info.fetch("service_unit_tests_passed")
        assert_equal false, info.fetch("job_integration_verified")
        assert_equal false, info.fetch("ticket_acceptance_verified")
        assert_equal false, info.fetch("gatekeeper_approved")
        assert File.file?(File.join(destination, "manifest.json"))
        assert File.file?(File.join(destination, "ticket_traceability.json"))
        assert File.file?(File.join(destination, "reviewed_candidate/verification.json"))
        rel = "services/metadata_normalizer.rb"
        assert_equal info.fetch("artifact_sha256").fetch(rel), Digest::SHA256.file(File.join(destination, "reviewed_candidate", rel)).hexdigest
        assert_includes info.fetch("unit_test_output"), "REVIEWED_TEMPLATE_SERVICE_TESTS_PASS"
      end
    end
  end
  test "refuses existing destination without overwriting" do
    with_root do |root|
      Dir.mktmpdir("nevaeh-reviewed-outer-") do |parent|
        assert_raises(NevaehIntelligences::CapabilityCodeGeneratorV7a::Invalid) do
          NevaehIntelligences::ReviewedImplementationTemplateV7a.generate(ticket: @ticket, key: "test.normalize", root: root, destination: parent)
        end
      end
    end
  end
end
