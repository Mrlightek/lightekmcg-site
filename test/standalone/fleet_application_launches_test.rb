require_relative "../../app/services/gatekeeper/website_readiness"
require_relative "fleet_updates_test" unless defined?(FleetUpdatesTest)
%w[launches mail_port_request image_builds].each { |file| require Rails.root.join("app/services/gatekeeper/hosting", file).to_s }
require Rails.root.join("app/jobs/gatekeeper/hosting/launch_application_job").to_s
require Rails.root.join("app/jobs/gatekeeper/hosting/mail_port_request_job").to_s
require Rails.root.join("app/services/gatekeeper/compute/linode_catalog_service").to_s

class FleetUpdatesTest
  def docker_template(**attributes)
    GatekeeperApplicationTemplate.create!({name: "Studio design", kind: "docker", image: "ghcr.io/lightek/design@sha256:#{'a' * 64}"}.merge(attributes))
  end

  def test_template_requires_a_digest_and_retired_templates_are_unavailable
    template = docker_template
    refute template.update(image: "ghcr.io/lightek/design:latest")
    template.reload.update!(enabled: false)
    refute_includes GatekeeperApplicationTemplate.available, template
  end

  def test_existing_server_launch_reserves_domain_and_copies_template_without_allocating
    admin = hosting_owner("super_admin")
    node, = hosting_server(admin)
    template = docker_template
    launch = Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: {
      "template_id" => template.id, "node_id" => node.id, "name" => "Client store", "domain" => "new-client.example.com"})
    assert_equal node, launch.gatekeeper_node
    assert_nil launch.provisioning_request
    assert_equal 1, GatekeeperNode.count
    assert_equal template.image, launch.template_snapshot["image"]
    template.update!(image: "ghcr.io/lightek/design@sha256:#{'b' * 64}")
    assert_equal "ghcr.io/lightek/design@sha256:#{'a' * 64}", launch.reload.template_snapshot["image"]
    assert_includes Gatekeeper::Hosting::Access.site_domains(admin), launch.domain
    assert_equal launch.id, ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args].first
  end

  def test_customer_cannot_install_arbitrary_images_or_allocate_a_server
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      Gatekeeper::Hosting::Launches.create!(actor: hosting_owner, attributes: {})
    end
    assert_equal 0, GatekeeperApplicationLaunch.count
  end

  def test_cannot_install_on_deleting_server_or_reuse_existing_domain
    admin = hosting_owner("super_admin")
    node, project = hosting_server(admin)
    template = docker_template
    values = {"template_id" => template.id, "node_id" => node.id, "name" => "Client", "domain" => project.domain}
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: values) }
    node.update!(status: "deleting")
    values["domain"] = "unused.example.com"
    assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: values) }
  end

  def test_queued_application_blocks_server_deletion
    admin = hosting_owner("super_admin")
    node, = hosting_server(admin)
    Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: {"template_id" => docker_template.id,
      "node_id" => node.id, "name" => "Client", "domain" => "unused.example.com"})
    assert_raises(Gatekeeper::Hosting::Access::Denied) do
      Gatekeeper::Hosting::Deletions.request!(actor: admin, node: node, confirmation: node.name)
    end
    assert_equal "healthy", node.reload.status
  end

  def test_provider_mail_request_matches_approved_customer_wording
    body = Gatekeeper::Hosting::MailPortRequest.description(ip: "203.0.113.44", domain: "client.example.com", hostname: "mail.client.example.com")
    assert_includes body, "on my Linode at 203.0.113.44 for the domain client.example.com"
    assert_includes body, "The server hostname is mail.client.example.com."
    assert_includes body, "ports 25, 465, and 587"
    assert_includes body, "SPF, DKIM, DMARC, reverse DNS, rate limits, and abuse protections"
    refute_includes body, "993"
  end

  def test_mail_request_is_idempotent_and_saves_provider_ticket_id
    admin = hosting_owner("super_admin")
    node, = hosting_server(admin)
    node.compute_provider.update!(slug: "linode")
    request = ProvisioningRequest.create!(owner: admin, gatekeeper_node: node, compute_provider: node.compute_provider,
      metadata: {}, requested_node_count: 1)
    calls = []
    adapter = Object.new
    adapter.define_singleton_method(:create_support_ticket) { |**args| calls << args; {"id" => 123} }
    ComputeProvider.test_adapter = adapter
    2.times { Gatekeeper::Hosting::MailPortRequest.submit!(request: request.reload, actor: admin, domain: "client.example.com") }
    assert_equal 1, calls.size
    assert_equal 123, request.reload.metadata["mail_port_ticket_id"]
  end
  def test_new_server_launch_uses_provider_catalog_price_and_approved_request
    admin = hosting_owner("super_admin")
    provider = ComputeProvider.create!(name: "Linode", slug: "linode")
    provider.define_singleton_method(:health_status) { "healthy" }
    catalog = {"plans" => [{"id" => "g6-standard-2", "monthly_cents" => 2400}],
      "regions" => [{"id" => "us-east"}], "images" => [{"id" => "linode/ubuntu24.04"}]}
    scope = Object.new
    scope.define_singleton_method(:find) { |_id| provider }
    values = {"template_id" => docker_template.id, "name" => "New server", "domain" => "fresh.example.com",
      "compute_provider_id" => provider.id, "plan" => "g6-standard-2", "region" => "us-east"}
    ComputeProvider.stub(:active, scope) do
      Gatekeeper::Compute::LinodeCatalogService.stub(:call, catalog) do
        launch = Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: values)
        request = launch.provisioning_request
        assert_equal 2400, request.estimated_monthly_cost_cents
        assert_equal "approved", request.approval_status
        assert_equal "ready", request.execution_status
        assert_equal "linode/ubuntu24.04", request.selected_image
        assert_equal admin, request.owner
        assert_nil launch.gatekeeper_node_id
        assert_equal 0, GatekeeperNode.count
        values["domain"] = "other.example.com"
        values["plan"] = "made-up-plan"
        assert_raises(Gatekeeper::Hosting::Access::Denied) { Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: values) }
        assert_equal 1, ProvisioningRequest.count
      end
    end
  end

  def test_failed_container_installation_reuses_the_same_server_and_becomes_ready_on_retry
    admin = hosting_owner("super_admin")
    node, = hosting_server(admin)
    launch = Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: {"template_id" => docker_template.id,
      "node_id" => node.id, "name" => "Client", "domain" => "retry.example.com"})
    Gatekeeper::Hosting::Dns.stub(:prepare!, nil) do
      Gatekeeper::Fleet::Transport.stub(:run!, ->(**) { raise RuntimeError, "simulated failure" }) do
        assert_raises(RuntimeError) { Gatekeeper::Hosting::Launches.perform!(launch) }
      end
      assert_equal "failed", launch.reload.status
      assert_equal node.id, launch.gatekeeper_node_id
      receipt = {"status" => "succeeded", "domain" => launch.domain, "image" => launch.template_snapshot["image"]}
      Gatekeeper::Fleet::Transport.stub(:run!, receipt) { Gatekeeper::Hosting::Launches.perform!(launch) }
      assert_equal "ready", launch.reload.status
      assert_equal 1, GatekeeperNode.count
      assert_equal 0, ProvisioningRequest.count
      assert_equal ["failed", "succeeded"], GatekeeperOperation.order(:id).pluck(:status)
    end
  end

  def test_recovery_fails_stale_installation_and_requeues_queued_launches
    admin = hosting_owner("super_admin")
    node, = hosting_server(admin)
    launch = Gatekeeper::Hosting::Launches.create!(actor: admin, attributes: {"template_id" => docker_template.id,
      "node_id" => node.id, "name" => "Client", "domain" => "stale.example.com"})
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    Gatekeeper::Hosting::RecoveryJob.perform_now
    assert ActiveJob::Base.queue_adapter.enqueued_jobs.any? { |job| job[:job] == Gatekeeper::Hosting::LaunchApplicationJob && job[:args] == [launch.id] }
    launch.update_columns(status: "provisioning", updated_at: 3.hours.ago)
    Gatekeeper::Hosting::RecoveryJob.perform_now
    assert_equal "failed", launch.reload.status
    assert_equal node.id, launch.gatekeeper_node_id
  end

end
