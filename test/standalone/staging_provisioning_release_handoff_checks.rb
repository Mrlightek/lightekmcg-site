# frozen_string_literal: true

require_relative "staging_provisioning_dashboard_checks"
require "active_job"

class ApplicationController < DymondDash::ApplicationController; end
class ApplicationJob < ActiveJob::Base; end
ApplicationJob.queue_adapter = :test

class ApplicationRecord
  def self.has_one_attached(*) = nil
end

ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition.alias_method :jsonb, :json
require_relative "../../db/migrate/20261124210000_create_release_assurance"
CreateReleaseAssurance.new.migrate(:up)

%w[source policy readiness staging].each { |name| require_relative "../../app/services/release_assurance/#{name}" }
%w[candidate environment tester assignment run defect].each { |name| require_relative "../../app/models/release_assurance/#{name}" }
require_relative "../../app/jobs/release_assurance/deployment_job"
require_relative "../../app/controllers/dashboard/release_assurance_controller"
Dashboard::ReleaseAssuranceController.append_view_path File.expand_path("../../app/views", __dir__)
Rails.application.routes.disable_clear_and_finalize = true
Rails.application.routes.draw do
  instance_eval(File.read(File.expand_path("../../config/routes/release_assurance.rb", __dir__)))
end
Rails.application.routes.disable_clear_and_finalize = false

class StagingProvisioningDashboardChecks
  test "Release Assurance attaches the approved request and retains the approved cap and expiry" do
    old_runner = ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"]
    ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"] = "1"
    authenticate(@operator)
    get "/dashboard/infrastructure/provisioning/new"
    Gatekeeper::Compute::LinodeCatalogService.stub(:call, CATALOG) { submit_form("Prepare for approval") }
    follow_redirect!
    request = ProvisioningRequest.last
    submit_form("Approve")
    follow_redirect!
    assert_equal "approved", request.reload.approval_status
    approved_expiry = Time.iso8601(request.metadata.fetch("staging_provisioning").fetch("expires_at"))
    token = csrf_token

    candidate = ReleaseAssurance::Candidate.create!(operator: @operator, name: "Reviewed MSP", profile: "msp",
      publication_key: SecureRandom.uuid, selectors: [], source_sha: "a" * 40, state: "published")
    path = "/dashboard/release_assurance/#{candidate.id}"
    fields = { authenticity_token: token, request_id: request.id, hostname: HOSTNAME, hours: 168 }
    post "#{path}/prepare", params: fields.merge(budget_cents: 2401)
    assert_response :see_other
    assert_empty candidate.environments
    post "#{path}/prepare", params: fields.merge(budget_cents: 2400)
    assert_response :see_other

    environment = candidate.environments.sole
    assert_equal request.id, environment.provisioning_request_id
    assert_equal approved_expiry, environment.expires_at
    assert_equal 2400, environment.budget_cents
    assert_equal "prepared", environment.state
    assert_equal ["prepared", "approved", "attached to candidate #{candidate.id}"], audit_actions(request.reload)
    assert_empty ApplicationJob.queue_adapter.enqueued_jobs

    staging = ReleaseAssurance::Staging.new(environment, @operator)
    assert_equal ["lightekmcg.com", "batch-d-msp-r1.staging"], staging.send(:dns_target!)
    ENV["GODADDY_DOMAINS"] = "lightekmcg.com,staging.lightekmcg.com"
    assert_raises(ReleaseAssurance::Policy::Denied) { staging.send(:dns_target!) }
    ENV["GODADDY_DOMAINS"] = "lightekmcg.com"

    forbid_execution do
      post "#{path}/deploy", params: { authenticity_token: token, environment_id: environment.id }
      assert_response :see_other
      assert_equal "approved", environment.reload.state
      assert_equal ReleaseAssurance::DeploymentJob, ApplicationJob.queue_adapter.enqueued_jobs.sole.fetch(:job)
      assert_nil request.reload.gatekeeper_node_id
    end
  ensure
    ENV["LIGHTEK_RELEASE_ASSURANCE_RUNNER"] = old_runner
    ApplicationJob.queue_adapter.enqueued_jobs.clear
    ReleaseAssurance::Environment.where(candidate: candidate).delete_all if candidate
    candidate&.destroy!
  end

  test "staging publication refuses an existing record and records the created record ID" do
    dns = Object.new
    def dns.records = []
    def dns.create_record!(attributes) = attributes.merge("recordId" => "dns-42")
    target = ["lightekmcg.com", "batch-d-msp-r1.staging"]
    args = { hostname: HOSTNAME, ipv4: "8.8.4.4", replace: false, expected_target: target }

    Godaddy::DnsService.stub(:new, dns) do
      Resolv.stub(:getaddresses, ["8.8.4.4"]) do
        result = Gatekeeper::WebsiteDnsPublication.call!(**args) do |receipt|
          assert_equal({"zone" => target.first, "name" => target.last, "record_id" => "dns-42", "ipv4" => "8.8.4.4"}, receipt)
        end
        assert result.fetch("verified")
      end
      dns.stub(:records, [{"name" => target.last, "type" => "CNAME"}]) do
        assert_raises(Gatekeeper::WebsiteDnsPublication::Conflict) do
          Gatekeeper::WebsiteDnsPublication.call!(**args) { flunk "unexpected DNS write" }
        end
      end
      assert_raises(Gatekeeper::WebsiteDnsPublication::Conflict) do
        Gatekeeper::WebsiteDnsPublication.call!(**args.merge(expected_target: ["example.com", target.last]))
      end
    end
  end

end
