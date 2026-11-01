# Additional hosting contracts loaded by fleet_updates_test.rb.
require_relative "fleet_updates_test" unless defined?(FleetUpdatesTest)
require Rails.root.join("app/services/lightek_settings/site_domain").to_s
require Rails.root.join("app/models/gatekeeper_hosted_application").to_s
%w[access runtime applications deletions dns site_routing].each { |file| require Rails.root.join("app/services/gatekeeper/hosting", file).to_s }
%w[provision_application_job delete_server_job recovery_job].each { |file| require Rails.root.join("app/jobs/gatekeeper/hosting", file).to_s }
require Rails.root.join("app/services/gatekeeper/compute/deprovisioning_service").to_s
require Rails.root.join("app/services/gatekeeper/compute/provider").to_s
require Rails.root.join("app/services/gatekeeper/compute/providers/http_support").to_s
require Rails.root.join("app/services/gatekeeper/compute/providers/linode_adapter").to_s

class FleetUpdatesTest
  class DeleteAdapter
    attr_reader :ids
    attr_accessor :failure
    def initialize = @ids = []
    def destroy_node(id)
      @ids << id
      raise failure if failure
      true
    end
  end

  def hosting_owner(role = "client")
    User.create!(email_address: "owner-#{SecureRandom.hex(5)}@example.com", role: role)
  end

  def hosting_server(owner = hosting_owner)
    provider = ComputeProvider.create!(name: "Configured cloud", slug: "ovh")
    node = GatekeeperNode.create!(name: "server-#{SecureRandom.hex(5)}", ip_address: "203.0.113.44", ssh_user: "root",
      owner: owner, compute_provider: provider, provider_resource_id: "vps-987", status: "healthy")
    project = GatekeeperProject.create!(name: "runtime-#{node.id}", gatekeeper_node_id: node.id,
      domain: "primary-#{node.id}.example.com", app_root: "/var/www/customer", app_user: "lightek",
      repository: Gatekeeper::Fleet::Adapters::MAIN_REPOSITORY, metadata: {})
    [node, project]
  end

  def hosting_plan(owner, max_sites = 2, **changes)
    SubscriptionInfrastructureEntitlement.create!(subscription_plan_id: 1, max_sites: max_sites)
    DymondBank::Subscription.create!({subscriber: owner, plan_id: 1, status: "active",
      current_period_start: 1.hour.ago, current_period_end: 1.month.from_now}.merge(changes))
  end

  def hosted_site(actor:, node:, project:, owner: actor, domain: "extra.example.com")
    Gatekeeper::Hosting::Applications.create!(actor: actor, node: node, project: project, owner: owner,
      name: "Customer application", domain: domain)
  end

  def test_server_scope_exposes_only_customer_owned_nodes_and_super_admin_sees_all
    owner = hosting_owner
    node, = hosting_server(owner)
    other, = hosting_server
    assert_equal [node.id], Gatekeeper::Hosting::Access.nodes(owner).pluck(:id)
    assert_equal 2, Gatekeeper::Hosting::Access.nodes(hosting_owner("super_admin")).count
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Access.authorize!(owner, other) }
  end

  def test_customer_private_domain_is_rejected_before_creating_a_reservation
    owner = hosting_owner("super_admin")
    node, project = hosting_server(owner)
    count = GatekeeperHostedApplication.count
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      hosted_site(actor: owner, node: node, project: project, domain: "192.168.64.2")
    end
    assert_equal count, GatekeeperHostedApplication.count
  end

  def test_second_application_uses_existing_node_and_reserves_plan_capacity
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner, 2)
    app = hosted_site(actor: owner, node: node, project: project)
    assert_equal node.id, app.gatekeeper_node_id
    assert_equal "queued", app.status
    assert_equal 1, GatekeeperNode.count
    assert_equal 2, Gatekeeper::Hosting::Access.site_domains(owner).size
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      hosted_site(actor: owner, node: node, project: project, domain: "third.example.com")
    end
    app.update!(status: "failed")
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      hosted_site(actor: owner, node: node, project: project, domain: "third.example.com")
    end
  end

  def test_super_admin_can_create_for_any_account_without_plan_or_site_cap
    owner = hosting_owner
    node, project = hosting_server(owner)
    app = hosted_site(actor: hosting_owner("super_admin"), node: node, project: project, owner: owner)
    assert_equal owner.id, app.owner_id
  end

  def test_expired_or_unpaid_subscription_does_not_grant_more_sites
    owner = hosting_owner
    hosting_plan(owner, 10, current_period_end: 1.second.ago)
    assert_equal 0, Gatekeeper::Hosting::Access.site_limit(owner)
    DymondBank::Subscription.update_all(current_period_end: 1.month.from_now, status: "past_due")
    assert_equal 0, Gatekeeper::Hosting::Access.site_limit(owner)
    DymondBank::Subscription.update_all(status: "trialing", trial_ends_at: nil)
    assert_equal 0, Gatekeeper::Hosting::Access.site_limit(owner)
  end

  def test_customer_cannot_place_apps_on_another_server_or_assign_foreign_accounts
    owner = hosting_owner
    node, project = hosting_server
    assert_raises(Gatekeeper::Hosting::Access::Denied) { hosted_site(actor: owner, node: node, project: project) }
    mine, runtime = hosting_server(owner)
    hosting_plan(owner)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { hosted_site(actor: owner, node: mine, project: runtime, owner: node.owner) }
    assert_raises(Gatekeeper::Hosting::Access::Denied) { hosted_site(actor: owner, node: mine, project: project) }
  end

  def test_native_application_job_records_real_routing_receipt_without_allocating_compute
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner)
    app = hosted_site(actor: owner, node: node, project: project)
    Gatekeeper::Hosting::Dns.stub(:prepare!, ->(**) { true }) do
      Gatekeeper::Fleet::Transport.stub(:run!, ->(**args) {
        assert_equal node.id, args[:node].id
        assert_equal "create_hosted_site.py", args[:script_name]
        assert_equal owner.email_address, args[:payload][:owner_email]
        {"status" => "succeeded", "domain" => app.domain, "application_key" => app.public_key, "site_id" => 42}
      }) { Gatekeeper::Hosting::Applications.provision!(app) }
    end
    assert_equal "ready", app.reload.status
    assert_equal 42, app.remote_site_id
    assert_equal "succeeded", app.gatekeeper_operation.status
    assert_equal 1, GatekeeperNode.count
  end

  def test_wrong_application_receipt_fails_and_retry_keeps_same_identity
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner)
    app = hosted_site(actor: owner, node: node, project: project)
    key = app.public_key
    Gatekeeper::Hosting::Dns.stub(:prepare!, ->(**) {}) do
      Gatekeeper::Fleet::Transport.stub(:run!, ->(**) { {"status" => "succeeded", "domain" => "wrong.example.com"} }) do
        Gatekeeper::Hosting::Applications.provision!(app)
      end
    end
    assert_equal "failed", app.reload.status
    Gatekeeper::Hosting::Applications.retry!(actor: owner, app: app)
    assert_equal key, app.reload.public_key
    assert_equal 1, GatekeeperHostedApplication.count
  end

  def test_server_delete_requires_typed_confirmation_and_records_queue_before_provider_call
    owner = hosting_owner
    node, = hosting_server(owner)
    ComputeProvider.test_adapter = DeleteAdapter.new
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: "wrong")
    end
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    assert_equal "deleting", node.reload.status
    assert_equal owner.id, request.metadata["delete_actor_id"]
    assert_empty ComputeProvider.test_adapter.ids
  end

  def test_provider_deletion_is_idempotent_and_keeps_audit_history
    owner = hosting_owner
    node, project = hosting_server(owner)
    ComputeProvider.test_adapter = DeleteAdapter.new
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    2.times { Gatekeeper::Hosting::Deletions.execute!(request: request, actor: owner) }
    assert_equal ["vps-987"], ComputeProvider.test_adapter.ids
    assert_equal "decommissioned", node.reload.status
    assert request.reload.destroyed_at
    assert GatekeeperNode.exists?(node.id)
    assert GatekeeperProject.exists?(project.id)
    assert_equal 2, GatekeeperOperation.where(capability: "destroy_compute_node", status: "succeeded").count
  end

  def test_server_deletion_disables_updates_and_marks_hosted_applications_deleted
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner)
    app = hosted_site(actor: owner, node: node, project: project)
    item = GatekeeperInstallation.create!(gatekeeper_node: node, domain: project.domain, adapter: "docker_compose", account: owner)
    ComputeProvider.test_adapter = DeleteAdapter.new
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    Gatekeeper::Hosting::Deletions.execute!(request: request, actor: owner)
    assert_equal "deleted", app.reload.status
    refute item.reload.enabled?
    refute item.eligible?
  end

  def test_cloud_error_does_not_report_server_deleted_and_can_be_retried
    owner = hosting_owner
    node, = hosting_server(owner)
    adapter = ComputeProvider.test_adapter = DeleteAdapter.new
    adapter.failure = RuntimeError.new("private-provider-payload")
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    assert_raises(RuntimeError) { Gatekeeper::Hosting::Deletions.execute!(request: request, actor: owner) }
    assert_equal "delete_failed", node.reload.status
    assert_nil request.reload.destroyed_at
    refute_includes GatekeeperOperation.last.error_message, "private-provider-payload"
    adapter.failure = nil
    Gatekeeper::Hosting::Deletions.execute!(request: request, actor: owner)
    assert_equal "decommissioned", node.reload.status
  end

  def test_deletion_binding_change_prevents_deleting_a_different_resource
    owner = hosting_owner
    node, = hosting_server(owner)
    ComputeProvider.test_adapter = DeleteAdapter.new
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    node.update!(provider_resource_id: "replacement-vps")
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Deletions.execute!(request: request, actor: owner) }
    assert_empty ComputeProvider.test_adapter.ids
  end

  def test_customers_cannot_delete_shared_servers_but_super_admin_can
    owner = hosting_owner
    node, project = hosting_server(owner)
    other = hosting_owner
    hosted_site(actor: hosting_owner("super_admin"), node: node, project: project, owner: other)
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    end
    request = Gatekeeper::Hosting::Deletions.request!(actor: hosting_owner("super_admin"), node: node, confirmation: node.name)
    assert_equal "approved", request.destroy_approval_status
  end

  def test_running_application_setup_blocks_server_deletion
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner)
    app = hosted_site(actor: owner, node: node, project: project)
    app.update!(status: "provisioning", started_at: Time.current)
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name) }
    assert_equal "healthy", node.reload.status
  end

  def test_linode_delete_retry_treats_only_provider_404_as_already_removed
    adapter = Gatekeeper::Compute::Providers::LinodeAdapter.new(provider: Object.new)
    error = Gatekeeper::Compute::Providers::HttpSupport::RequestError
    adapter.stub(:request, ->(*) { raise error.new(404, "not found") }) { assert adapter.destroy_node(42) }
    adapter.stub(:request, ->(*) { raise error.new(403, "denied") }) do
      assert_raises(error) { adapter.destroy_node(42) }
    end
  end

  def test_recovery_releases_stale_setup_operations_and_recovers_lost_enqueue
    owner = hosting_owner
    node, project = hosting_server(owner)
    hosting_plan(owner)
    app = hosted_site(actor: owner, node: node, project: project)
    operation = GatekeeperOperation.create!(gatekeeper_node: node, capability: "create_hosted_application",
      requested_by: owner.email_address, status: "running", started_at: 2.hours.ago)
    app.update!(status: "provisioning", started_at: 2.hours.ago, gatekeeper_operation: operation)
    Gatekeeper::Hosting::RecoveryJob.new.perform
    assert_equal "failed", app.reload.status
    assert_equal "failed", operation.reload.status
    request = Gatekeeper::Hosting::Deletions.request!(actor: owner, node: node, confirmation: node.name)
    assert_equal "queued", request.metadata["delete_state"]
  end

  def test_managed_server_transport_refuses_unregistered_scripts
    assert_raises(ArgumentError) do
      Gatekeeper::Fleet::Transport.run!(node: Object.new, domain: "example.com", requested_by: "test",
        operation_id: nil, payload: {}, script_name: "../../untrusted.py")
    end
  end

  def test_application_markup_preserves_design_studio_preview_without_site_manifest
    require "erb"
    line = Rails.root.join("app/views/layouts/lightek_design/website.html.erb").read.lines.find { |text| text.include?("lightek-application-key") }
    @preview = true
    @site = Struct.new(:name, :id).new("Design preview", nil)
    assert_empty ERB.new(line).result(binding).strip
    @preview = false
    @site = Struct.new(:manifest).new({"hosted_application_key" => "application-123"})
    assert_includes ERB.new(line).result(binding), 'content="application-123"'
  end
end
