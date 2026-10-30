# frozen_string_literal: true
require "test_helper"
class GatekeeperWebsiteDeploymentTest < ActiveSupport::TestCase
  def with_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name) { |*args, **kwargs, &block| implementation.call(*args, **kwargs, &block) }
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end

  def actor(role = "super_admin")
    User.create!(email_address: "deployment-#{SecureRandom.hex(8)}@example.test",
      first_name: "Deploy", last_name: "Test", role:, password: "test-password-123")
  end

  def target
    GatekeeperNode.create!(name: "deploy-#{SecureRandom.hex(8)}", ip_address: "203.0.113.44", ssh_user: "root", ssh_port: 22)
  end

  def configuration(owner:, internal: false)
    Gatekeeper::WebsiteDeployment.configuration(owner:, domain: "demo.example.test",
      site_name: "Demo", headline: "Hello", description: "Example", certificate_email: "cert@example.test",
      credential_slug: "deployment-test", internal:)
  end

  test "ordinary admin cannot configure or preview deployments" do
    user = actor("admin")
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
      Gatekeeper::WebsiteDeployment.preview(actor: user, record: target, domain: "demo.example.test")
    end
  end

  test "customer and internal installation roles are explicit" do
    owner = actor
    assert_equal "admin", configuration(owner:)["owner_role"]
    assert_equal "super_admin", configuration(owner:, internal: true)["owner_role"]
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) { configuration(owner: actor("client"), internal: true) }
  end

  test "registration and preview preserve unrelated node metadata without reading secrets" do
    owner = actor
    node = target
    node.update!(metadata: {"preserved" => "yes"})
    deny_checkout = ->(**) { flunk "preview must not read Vault payloads" }
    with_stub(LightekVault::Service, :checkout!, deny_checkout) do
      2.times { Gatekeeper::WebsiteDeployment.register!(actor: owner, record: node, config: configuration(owner:)) }
      view = Gatekeeper::WebsiteDeployment.preview(actor: owner, record: node, domain: "demo.example.test")
      assert_equal owner.email_address, view["owner_email"]
      assert_equal "existing_node", view["target"]
    end
    assert_equal "yes", node.reload.metadata["preserved"]
    assert_equal 1, node.metadata["website_deployments"].size
    refute_includes node.metadata.to_json, "owner_password"
  end

  test "existing hostname cannot be assigned to another owner" do
    admin = actor
    node = target
    Gatekeeper::WebsiteDeployment.register!(actor: admin, record: node, config: configuration(owner: admin))
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
      Gatekeeper::WebsiteDeployment.register!(actor: admin, record: node, config: configuration(owner: actor("client")))
    end
  end

  test "full hostname is required" do
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
      Gatekeeper::WebsiteDeployment.configuration(owner: actor, domain: "octavia", site_name: "Demo",
        headline: "Hello", description: "Example", certificate_email: "cert@example.test", credential_slug: "test")
    end
  end

  test "DNS credentials cannot override deployment or database environment" do
    assert_equal({"GODADDY_PAT" => "test-token"}, Gatekeeper::WebsiteDeployment.dns_environment({"dns_env" => {"GODADDY_PAT" => "test-token"}}))
    assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
      Gatekeeper::WebsiteDeployment.dns_environment({"dns_env" => {"DATABASE_URL" => "postgres://other"}})
    end
  end

  test "pending provisioning request is refused before calling provider" do
    admin = actor
    request = ProvisioningRequest.create!(owner: admin, approval_status: "pending", execution_status: "awaiting_approval", requested_node_count: 1)
    Gatekeeper::WebsiteDeployment.register!(actor: admin, record: request, config: configuration(owner: admin))
    with_stub(Gatekeeper::Compute::ProvisioningExecutionService, :call, ->(**) { flunk "pending request reached provider" }) do
      assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
        Gatekeeper::WebsiteDeployment.provision_and_run!(actor: admin, request:, domain: "demo.example.test")
      end
    end
  end

  test "Vault denial records a failed operation and escalates without storing its payload" do
    admin = actor
    node = target
    Gatekeeper::WebsiteDeployment.register!(actor: admin, record: node, config: configuration(owner: admin))
    secret_marker = "do-not-store-this-credential"
    with_stub(LightekVault::Service, :checkout!, ->(**args) {
      assert_equal "Gatekeeper::WebsiteDeployment", args[:consumer]
      assert_equal "website_deploy", args[:purpose]
      raise LightekVault::Service::AccessDenied, secret_marker
    }) do
      with_stub(Gatekeeper::KnowledgeService, :find_for_failure, ->(**) { [] }) do
        with_stub(Gatekeeper::SupportTicketService, :open_for_failure!, ->(**args) {
          refute_includes args[:error].message, secret_marker
          Struct.new(:id, :number).new(987, "TEST-987")
        }) do
          assert_raises(Gatekeeper::WebsiteDeployment::Invalid) do
            Gatekeeper::WebsiteDeployment.run!(actor: admin, node:, domain: "demo.example.test")
          end
        end
      end
    end
    operation = GatekeeperOperation.where(gatekeeper_node: node, capability: "deploy_website").order(:id).last
    assert_equal "failed", operation.status
    assert_equal 987, operation.result["support_ticket_id"]
    refute_includes operation.attributes.to_json, secret_marker
  end

  test "retry reuses attached instance instead of allocating another" do
    admin = actor
    node = target
    request = ProvisioningRequest.create!(owner: admin, gatekeeper_node: node,
      approval_status: "approved", execution_status: "succeeded", requested_node_count: 1)
    Gatekeeper::WebsiteDeployment.register!(actor: admin, record: request, config: configuration(owner: admin))
    with_stub(Gatekeeper::Compute::ProvisioningExecutionService, :call, ->(**) { flunk "retry allocated a duplicate" }) do
      with_stub(Gatekeeper::Compute::NodeVerificationService, :call, ->(**) { {provider_status: "running"} }) do
        with_stub(Gatekeeper::WebsiteDnsPublication, :call!, ->(**) { {"verified" => true} }) do
          with_stub(Gatekeeper::WebsiteDeployment, :run!, ->(actor:, node:, domain:) { {node_id: node.id, domain:} }) do
            result = Gatekeeper::WebsiteDeployment.provision_and_run!(actor: admin, request:, domain: "demo.example.test")
            assert_equal node.id, result[:node_id]
          end
        end
      end
    end
  end

  test "missing deployment credential prevents an otherwise executable allocation" do
    admin = actor
    request = ProvisioningRequest.create!(owner: admin, approval_status: "approved", execution_status: "ready", requested_node_count: 1)
    Gatekeeper::WebsiteDeployment.register!(actor: admin, record: request, config: configuration(owner: admin))
    with_stub(request, :executable?, -> { true }) do
      with_stub(LightekVault::Service, :checkout!, ->(**) { raise LightekVault::Service::AccessDenied, "consumer is not allowed" }) do
        with_stub(Gatekeeper::Compute::ProvisioningExecutionService, :call, ->(**) { flunk "credential failure allocated a provider instance" }) do
          assert_raises(LightekVault::Service::AccessDenied) do
            Gatekeeper::WebsiteDeployment.provision_and_run!(actor: admin, request:, domain: "demo.example.test")
          end
        end
      end
    end
    assert_nil request.reload.gatekeeper_node_id
  end
end
